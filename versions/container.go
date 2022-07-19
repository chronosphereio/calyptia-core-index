package versions

import (
	"encoding/json"
	"fmt"
	semver "github.com/hashicorp/go-version"
	"io"
	"net/http"
	"sort"
)

const (
	containerIndexURL = "https://raw.githubusercontent.com/calyptia/core-images-index/main/container.index.json"
)

type (
	ContainerImages []string

	//go:generate moq -out container_index_fetch_mock.go . ContainerIndexFetch
	ContainerIndexFetch interface {
		GetImages() (ContainerImages, error)
	}

	//go:generate moq -out container_index_mock.go . ContainerIndex
	ContainerIndex interface {
		Match(version string) (string, error)
	}

	Container struct {
		ContainerIndex
		Fetcher ContainerIndexFetcher
	}

	ContainerIndexFetcher struct {
		ContainerIndexFetch
	}
)

func (c *ContainerIndexFetcher) GetImages() (ContainerImages, error) {
	var out ContainerImages

	get, err := http.Get(containerIndexURL)
	if err != nil {
		return out, fmt.Errorf("could not fetch index %s: %w", containerIndexURL, err)
	}
	defer func(Body io.ReadCloser) {
		err := Body.Close()
		if err != nil {
			return
		}
	}(get.Body)

	err = json.NewDecoder(get.Body).Decode(&out)
	if err != nil {
		return out, fmt.Errorf("could not decode index response: %w", err)
	}

	return out, nil
}

func (c *Container) All() ([]string, error) {
	var out []string

	containerImages, err := c.Fetcher.GetImages()
	if err != nil {
		return out, fmt.Errorf("cannot get container index: %w", err)
	}

	var images semver.Collection
	for _, image := range containerImages {
		ver, err := semver.NewSemver(image)
		if err != nil {
			continue
		}
		images = append(images, ver)
	}

	sort.Sort(images)

	for _, image := range images {
		out = append(out, image.String())
	}

	return out, nil
}

func (c *Container) Last() (string, error) {
	versions, err := c.All()
	if err != nil {
		return "", err
	}
	return versions[len(versions)-1], nil
}

func NewContainer() (*Container, error) {
	return &Container{
		Fetcher: ContainerIndexFetcher{},
	}, nil
}

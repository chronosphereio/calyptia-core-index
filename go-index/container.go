package index

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"

	semver "github.com/hashicorp/go-version"
)

const (
	containerIndexURL = "https://raw.githubusercontent.com/calyptia/core-images-index/main/container.index.json"
)

type (
	ContainerImages []string

	//go:generate moq -out container_index_fetch_mock.go . ContainerIndexFetch
	ContainerIndexFetch interface {
		GetImages(ctx context.Context) (ContainerImages, error)
	}

	//go:generate moq -out container_index_mock.go . ContainerIndex
	ContainerIndex interface {
		All(ctx context.Context) ([]string, error)
		Last(ctx context.Context) (string, error)
		Match(ctx context.Context, version string) (string, error)
	}

	Container struct {
		ContainerIndex
		Fetcher ContainerIndexFetch
	}

	ContainerIndexFetcher struct {
		ContainerIndexFetch
	}
)

func (c *ContainerIndexFetcher) GetImages(ctx context.Context) (ContainerImages, error) {
	var out ContainerImages
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, containerIndexURL, nil)
	if err != nil {
		return out, fmt.Errorf("cannot create a request to index %s: %w", containerIndexURL, err)
	}

	client := http.DefaultClient
	res, err := client.Do(request)
	if err != nil {
		return out, fmt.Errorf("could not fetch index %s: %w", containerIndexURL, err)
	}

	defer func(Body io.ReadCloser) {
		err := Body.Close()
		if err != nil {
			return
		}
	}(res.Body)

	err = json.NewDecoder(res.Body).Decode(&out)
	if err != nil {
		return out, fmt.Errorf("could not decode index response: %w", err)
	}
	return out, nil
}

func (c *Container) All(ctx context.Context) ([]string, error) {
	var out []string

	containerImages, err := c.Fetcher.GetImages(ctx)
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
		out = append(out, image.Original())
	}

	return out, nil
}

func (c *Container) Match(ctx context.Context, version string) (string, error) {
	orig, err := semver.NewVersion(version)
	if err != nil {
		return "", err
	}

	containerImages, err := c.Fetcher.GetImages(ctx)
	if err != nil {
		return "", fmt.Errorf("cannot get images from container index: %w", err)
	}

	for _, imageTag := range containerImages {
		release, err := semver.NewVersion(imageTag)
		if err != nil {
			return "", err
		}
		if release.Equal(orig) {
			return imageTag, nil
		}
	}

	return "", ErrNoMatchingImage
}

func (c *Container) Last(ctx context.Context) (string, error) {
	versions, err := c.All(ctx)
	if err != nil {
		return "", err
	}
	return versions[len(versions)-1], nil
}

func NewContainer() (*Container, error) {
	return &Container{
		Fetcher: &ContainerIndexFetcher{},
	}, nil
}

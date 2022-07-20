// Package index this packages allows to consume the container and public cloud providers
// images index from Go. This is oriented to be used as a helper to determine the latest version
// as well as a matching release. See [./full_test.go](./full_test.go) for a working example.
package index

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	semver "github.com/hashicorp/go-version"
)

const (
	gcpIndexURL = "https://raw.githubusercontent.com/calyptia/core-images-index/main/gcp.index.json"
)

type (
	GCPImage struct {
		CreationTimestamp string `json:"creationTimestamp"`
		Labels            struct {
			CalyptiaCoreRelease string `json:"calyptia-core-release"`
			SourceImage         string `json:"source-image"`
		} `json:"labels"`
		Name string `json:"name"`
	}

	GCPImages []GCPImage

	//go:generate moq -out gcp_index_fetch_mock.go . GCPIndex
	GCPIndexFetch interface {
		GetImages() (GCPImages, error)
	}

	//go:generate moq -out gcp_index_mock.go . GCPIndex
	GCPIndex interface {
		Match(version string) (string, error)
	}

	GCP struct {
		GCPIndex
		Fetcher GCPIndexFetch
	}

	GCPIndexFetcher struct {
		GCPIndexFetch
	}
)

func (f GCPIndexFetcher) GetImages() (GCPImages, error) {
	var out GCPImages

	get, err := http.Get(gcpIndexURL)
	if err != nil {
		return out, fmt.Errorf("could not fetch index %s: %w", awsIndexURL, err)
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

func (g GCP) Match(version string) (string, error) {
	var images GCPImages

	orig, err := semver.NewVersion(version)
	if err != nil {
		return "", err
	}

	images, err = g.Fetcher.GetImages()
	if err != nil {
		return "", fmt.Errorf("error fetching images: %w", err)
	}

	for _, image := range images {
		release, err := semver.NewVersion(strings.ReplaceAll(image.Labels.CalyptiaCoreRelease, "-", "."))
		if err != nil {
			return "", err
		}
		if release.Equal(orig) {
			return image.Name, nil
		}
	}

	return "", ErrNoMatchingImage
}

func NewGCP() (*GCP, error) {
	return &GCP{
		Fetcher: GCPIndexFetcher{},
	}, nil
}

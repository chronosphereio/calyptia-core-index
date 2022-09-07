// Package index this packages allows to consume the container and public cloud providers
// images index from Go. This is oriented to be used as a helper to determine the latest version
// as well as a matching release. See [./full_test.go](./full_test.go) for a working example.
package index

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	semver "github.com/hashicorp/go-version"
)

const (
	gcpIndexURL     = "https://raw.githubusercontent.com/calyptia/core-images-index/main/gcp.index.json"
	gcpTestIndexURL = "https://raw.githubusercontent.com/calyptia/core-images-index/main/gcp.test.index.json"
)

type (
	GCPImage struct {
		CreationTimestamp string `json:"creationTimestamp"`
		Labels            struct {
			CalyptiaCoreRelease string `json:"calyptia-core-release"`
			SourceImage         string `json:"source-image"`
		} `json:"labels"`
		Name             string   `json:"name"`
		StorageLocations []string `json:"storageLocations"`
	}

	GCPImages []GCPImage

	//go:generate moq -out gcp_index_fetch_mock.go . GCPIndex
	GCPIndexFetch interface {
		GetImages(ctx context.Context, opts FilterOpts) (GCPImages, error)
	}

	//go:generate moq -out gcp_index_mock.go . GCPIndex
	GCPIndex interface {
		Match(ctx context.Context, opts FilterOpts) (string, error)
	}

	GCP struct {
		GCPIndex
		Fetcher GCPIndexFetch
	}

	GCPIndexFetcher struct {
		GCPIndexFetch
	}
)

func (f GCPIndexFetcher) GetImages(ctx context.Context, opts FilterOpts) (GCPImages, error) {
	var out GCPImages

	url := gcpIndexURL
	if opts.TestIndex {
		url = gcpTestIndexURL
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return out, fmt.Errorf("cannot create a request to index %s: %w", url, err)
	}

	client := http.DefaultClient
	res, err := client.Do(request)
	if err != nil {
		return out, fmt.Errorf("could not fetch index %s: %w", gcpIndexURL, err)
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

func (g GCP) Match(ctx context.Context, opts FilterOpts) (string, error) {
	var images GCPImages

	orig, err := semver.NewVersion(opts.Version)
	if err != nil {
		return "", err
	}

	images, err = g.Fetcher.GetImages(ctx, opts)
	if err != nil {
		return "", fmt.Errorf("error fetching images: %w", err)
	}

	for _, image := range images {
		release, err := semver.NewVersion(strings.ReplaceAll(image.Labels.CalyptiaCoreRelease, "-", "."))
		if err != nil {
			return "", err
		}
		if image.StorageLocations[0] == opts.Region && release.Equal(orig) {
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

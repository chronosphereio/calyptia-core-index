package index

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	semver "github.com/hashicorp/go-version"
)

const (
	awsIndexURL       = "https://raw.githubusercontent.com/calyptia/core-images-index/main/aws.index.json"
	awsCoreReleaseTag = "calyptia-core-release"
)

type (
	AWSImage struct {
		CreationDate time.Time `json:"CreationDate"`
		ImageID      string    `json:"ImageId"`
		Name         string    `json:"Name"`
		Tags         []struct {
			Key   string `json:"Key"`
			Value string `json:"Value"`
		} `json:"Tags"`
		Region  string `json:"region"`
		Release string `json:"release"`
	}

	AWSImages []AWSImage

	//go:generate moq -out aws_index_fetch_mock.go . AWSIndexFetch
	AWSIndexFetch interface {
		GetImages(ctx context.Context) (AWSImages, error)
	}

	//go:generate moq -out aws_index_mock.go . AWSIndex
	AWSIndex interface {
		Match(ctx context.Context, region, version string) (string, error)
	}

	AWS struct {
		AWSIndex
		Fetcher AWSIndexFetch
	}

	AWSIndexFetcher struct {
		AWSIndexFetch
	}
)

func (f AWSIndexFetcher) GetImages(ctx context.Context) (AWSImages, error) {
	var out AWSImages

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, awsIndexURL, nil)
	if err != nil {
		return out, fmt.Errorf("cannot create a request to index %s: %w", awsIndexURL, err)
	}

	client := http.DefaultClient
	res, err := client.Do(request)
	if err != nil {
		return out, fmt.Errorf("could not fetch index %s: %w", awsIndexURL, err)
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

func (a AWS) Match(ctx context.Context, region, version string) (string, error) {
	var images AWSImages

	orig, err := semver.NewVersion(version)
	if err != nil {
		return "", err
	}

	images, err = a.Fetcher.GetImages(ctx)
	if err != nil {
		return "", err
	}

	for _, image := range images {
		release, err := semver.NewSemver(image.Release)
		if err != nil {
			return "", err
		}
		if image.Region == region && release.Equal(orig) {
			return image.ImageID, nil
		}
	}

	return "", ErrNoMatchingImage
}

func NewAWS() (*AWS, error) {
	return &AWS{
		Fetcher: AWSIndexFetcher{},
	}, nil
}

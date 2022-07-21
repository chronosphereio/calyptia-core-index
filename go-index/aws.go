package index

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	semver "github.com/hashicorp/go-version"
)

const (
	awsIndexURL       = "https://raw.githubusercontent.com/calyptia/core-images-index/main/aws.index.json"
	awsCoreReleaseTag = "calyptia-core-release"
)

type (
	AWSImage struct {
		CreationDate string `json:"CreationDate"`
		ImageID      string `json:"ImageId"`
		Name         string `json:"Name"`
		Tags         []struct {
			Key   string `json:"Key"`
			Value string `json:"Value"`
		} `json:"Tags"`
	}

	AWSImages []AWSImage

	//go:generate moq -out aws_index_fetch_mock.go . AWSIndexFetch
	AWSIndexFetch interface {
		GetImages() (AWSImages, error)
	}

	//go:generate moq -out aws_index_mock.go . AWSIndex
	AWSIndex interface {
		Match(version string) (string, error)
	}

	AWS struct {
		AWSIndex
		Fetcher AWSIndexFetch
	}

	AWSIndexFetcher struct {
		AWSIndexFetch
	}
)

func (f AWSIndexFetcher) GetImages() (AWSImages, error) {
	var out AWSImages

	get, err := http.Get(awsIndexURL)
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

func (a AWS) Match(version string) (string, error) {
	var images AWSImages

	orig, err := semver.NewVersion(version)
	if err != nil {
		return "", err
	}

	images, err = a.Fetcher.GetImages()
	if err != nil {
		return "", err
	}

	for _, image := range images {
		for _, tag := range image.Tags {
			if tag.Key == awsCoreReleaseTag {
				release, err := semver.NewVersion(tag.Value)
				if err != nil {
					return "", err
				}
				if release.Equal(orig) {
					return image.ImageID, nil
				}
			}
		}
	}

	return "", ErrNoMatchingImage
}

func NewAWS() (*AWS, error) {
	return &AWS{
		Fetcher: AWSIndexFetcher{},
	}, nil
}

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
	operatorIndexURL = "https://raw.githubusercontent.com/calyptia/core-images-index/main/operator.index.json"
)

type (
	OperatorImages []string

	//go:generate moq -out operator_index_fetch_mock.go . OperatorIndexFetch
	OperatorIndexFetch interface {
		GetImages(ctx context.Context) (OperatorImages, error)
	}

	//go:generate moq -out operator_index_mock.go . OperatorIndex
	OperatorIndex interface {
		All(ctx context.Context) ([]string, error)
		Last(ctx context.Context) (string, error)
		Match(ctx context.Context, version string) (string, error)
	}

	Operator struct {
		OperatorIndex
		Fetcher OperatorIndexFetch
	}

	OperatorIndexFetcher struct {
		OperatorIndexFetch
	}
)

func (c *OperatorIndexFetcher) GetImages(ctx context.Context) (OperatorImages, error) {
	var out OperatorImages
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, operatorIndexURL, nil)
	if err != nil {
		return out, fmt.Errorf("cannot create a request to index %s: %w", operatorIndexURL, err)
	}

	client := http.DefaultClient
	res, err := client.Do(request)
	if err != nil {
		return out, fmt.Errorf("could not fetch index %s: %w", operatorIndexURL, err)
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

func (c *Operator) All(ctx context.Context) ([]string, error) {
	var out []string

	operatorImages, err := c.Fetcher.GetImages(ctx)
	if err != nil {
		return out, fmt.Errorf("cannot get operator index: %w", err)
	}

	var images semver.Collection

	for _, image := range operatorImages {
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

func (c *Operator) Match(ctx context.Context, version string) (string, error) {
	orig, err := semver.NewVersion(version)
	if err != nil {
		return "", err
	}

	operatorImages, err := c.Fetcher.GetImages(ctx)
	if err != nil {
		return "", fmt.Errorf("cannot get images from operator index: %w", err)
	}

	for _, imageTag := range operatorImages {
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

func (c *Operator) Last(ctx context.Context) (string, error) {
	versions, err := c.All(ctx)
	if err != nil {
		return "", err
	}
	return versions[len(versions)-1], nil
}

func NewOperator() (*Operator, error) {
	return &Operator{
		Fetcher: &OperatorIndexFetcher{},
	}, nil
}

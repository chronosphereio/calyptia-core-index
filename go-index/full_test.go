package index

import (
	"context"
	"fmt"
	"testing"
)

func TestAll(t *testing.T) {
	versionToTest := "0.2.6"
	ctx := context.Background()

	container := Container{Fetcher: &ContainerIndexFetchMock{
		GetImagesFunc: func(ctx context.Context) (ContainerImages, error) {
			return ContainerImages{
				fmt.Sprintf("v%s", versionToTest),
			}, nil
		},
	}}

	lastImage, err := container.Last(ctx)
	if err != nil {
		t.Errorf("container last image error: %v != nil", err)
		return
	}

	if lastImage == "" {
		t.Errorf("container last image == empty")
		return
	}

	awsIndex := AWS{
		Fetcher: &AWSIndexFetchMock{
			GetImagesFunc: func(ctx context.Context) (AWSImages, error) {
				return AWSImages{
					AWSImage{
						ImageID: fmt.Sprintf("v%s", versionToTest),
						Name:    "test",
						Region:  "us-east-1",
						Release: versionToTest,
					},
				}, nil
			},
		},
	}

	match, err := awsIndex.Match(ctx, "us-east-1", lastImage)
	if err != nil {
		t.Errorf("aws index match err != nil, %s", err)
		return
	}

	if match != lastImage {
		t.Errorf("aws match: %s != %s", match, lastImage)
		return
	}

	gcpIndex := GCP{
		Fetcher: &GCPIndexFetchMock{
			GetImagesFunc: func(ctx context.Context) (GCPImages, error) {
				return GCPImages{
					GCPImage{
						Name: fmt.Sprintf("v%s", versionToTest),
						Labels: struct {
							CalyptiaCoreRelease string `json:"calyptia-core-release"`
							SourceImage         string `json:"source-image"`
						}{
							CalyptiaCoreRelease: "0-2-6",
						},
					},
				}, nil
			},
		},
	}

	match, err = gcpIndex.Match(ctx, lastImage)
	if err != nil {
		t.Errorf("gcp index match err != nil, %s", err)
		return
	}

	if match != lastImage {
		t.Errorf("gcp match: %s != %s", match, lastImage)
		return
	}
}

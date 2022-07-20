package index

import (
	"fmt"
	"testing"
)

func TestAll(t *testing.T) {
	versionToTest := "0.2.6"

	container := Container{Fetcher: &ContainerIndexFetchMock{
		GetImagesFunc: func() (ContainerImages, error) {
			return ContainerImages{
				fmt.Sprintf("v%s", versionToTest),
			}, nil
		},
	}}

	lastImage, err := container.Last()
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
			GetImagesFunc: func() (AWSImages, error) {
				return AWSImages{
					AWSImage{
						ImageID: fmt.Sprintf("v%s", versionToTest),
						Name:    "test",
						Tags: []struct {
							Key   string `json:"Key"`
							Value string `json:"Value"`
						}{
							{
								Key:   awsCoreReleaseTag,
								Value: versionToTest,
							},
						},
					},
				}, nil
			},
		},
	}

	match, err := awsIndex.Match(lastImage)
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
			GetImagesFunc: func() (GCPImages, error) {
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

	match, err = gcpIndex.Match(lastImage)
	if err != nil {
		t.Errorf("gcp index match err != nil, %s", err)
		return
	}

	if match != lastImage {
		t.Errorf("gcp match: %s != %s", match, lastImage)
		return
	}
}

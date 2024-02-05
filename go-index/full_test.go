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
}

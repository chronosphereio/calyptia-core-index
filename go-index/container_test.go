package index

import (
	"errors"
	"net/http"
	"reflect"
	"testing"
)

func TestContainer_All(t *testing.T) {
	tt := []struct {
		name           string
		container      Container
		wantedVersions []string
		wantError      error
	}{
		{
			name: "valid",
			container: Container{
				ContainerIndex: nil,
				Fetcher: &ContainerIndexFetchMock{
					GetImagesFunc: func() (ContainerImages, error) {
						return ContainerImages{
							"v0.2.6",
							"v0.2.4",
							"v0.2.3",
							"v0.2.2",
							"v0.2.1",
							"v0.1.1",
						}, nil
					},
				},
			},
			wantedVersions: ContainerImages{
				"v0.2.6",
				"v0.2.4",
				"v0.2.3",
				"v0.2.2",
				"v0.2.1",
				"v0.1.1",
			},
			wantError: nil,
		},
		{
			name: "error",
			container: Container{
				ContainerIndex: nil,
				Fetcher: &ContainerIndexFetchMock{
					GetImagesFunc: func() (ContainerImages, error) {
						return nil, http.ErrHijacked
					},
				},
			},
			wantError:      http.ErrHijacked,
			wantedVersions: []string{},
		},
	}

	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T) {
			versions, err := tc.container.All()
			if err != nil && tc.wantError != nil && !errors.Is(err, tc.wantError) {
				t.Errorf("error: %v != %v", err, tc.wantError)
				return
			}

			if want, got := tc.wantedVersions, versions; reflect.DeepEqual(want, got) {
				t.Errorf("want: %v != got: %v", want, got)
				return
			}
		})
	}
}

func TestContainer_Last(t *testing.T) {
	tt := []struct {
		name          string
		container     Container
		wantedVersion string
		wantError     error
	}{
		{
			name: "valid",
			container: Container{
				ContainerIndex: nil,
				Fetcher: &ContainerIndexFetchMock{
					GetImagesFunc: func() (ContainerImages, error) {
						return ContainerImages{
							"v0.2.6",
							"v0.2.4",
							"v0.2.3",
							"v0.2.2",
							"v0.2.1",
							"v0.1.1",
						}, nil
					},
				},
			},
			wantedVersion: "v0.2.6",
			wantError:     nil,
		},
		{
			name: "error",
			container: Container{
				ContainerIndex: nil,
				Fetcher: &ContainerIndexFetchMock{
					GetImagesFunc: func() (ContainerImages, error) {
						return nil, http.ErrHijacked
					},
				},
			},
			wantError: http.ErrHijacked,
		},
	}

	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T) {
			version, err := tc.container.Last()
			if err != nil && tc.wantError != nil && !errors.Is(err, tc.wantError) {
				t.Errorf("error: %v != %v", err, tc.wantError)
				return
			}
			if want, got := tc.wantedVersion, version; want != got {
				t.Errorf("want: %v != got: %v", want, got)
				return
			}
		})
	}
}

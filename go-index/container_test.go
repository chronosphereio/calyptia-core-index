package index

import (
	"context"
	"errors"
	"net/http"
	"reflect"
	"testing"
)

func TestContainer_Match(t *testing.T) {
	tt := []struct {
		name       string
		container  Container
		version    string
		wantedName string
		wantError  error
	}{
		{
			name: "valid",
			container: Container{
				Fetcher: &ContainerIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (ContainerImages, error) {
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
			version:    "v0.2.6",
			wantedName: "v0.2.6",
		},
		{
			name: "not found in index",
			container: Container{
				Fetcher: &ContainerIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (ContainerImages, error) {
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
			version:   "v0.2.5",
			wantError: ErrNoMatchingImage,
		},
		{
			name: "error getting images",
			container: Container{
				Fetcher: &ContainerIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (ContainerImages, error) {
						return nil, http.ErrHijacked
					},
				},
			},
			version:   "v0.2.6",
			wantError: http.ErrHijacked,
		},
	}

	ctx := context.Background()
	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T) {
			version, err := tc.container.Match(ctx, tc.version)
			if err != nil && tc.wantError != nil && !errors.Is(err, tc.wantError) {
				t.Errorf("error: %v != %v", err, tc.wantError)
				return
			}
			if want, got := tc.wantedName, version; want != got {
				t.Errorf("want: %v != got: %v", want, got)
				return
			}
		})
	}
}

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
					GetImagesFunc: func(ctx context.Context) (ContainerImages, error) {
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
					GetImagesFunc: func(ctx context.Context) (ContainerImages, error) {
						return nil, http.ErrHijacked
					},
				},
			},
			wantError:      http.ErrHijacked,
			wantedVersions: []string{},
		},
	}

	ctx := context.Background()
	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T) {
			versions, err := tc.container.All(ctx)
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
					GetImagesFunc: func(ctx context.Context) (ContainerImages, error) {
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
					GetImagesFunc: func(ctx context.Context) (ContainerImages, error) {
						return nil, http.ErrHijacked
					},
				},
			},
			wantError: http.ErrHijacked,
		},
	}

	ctx := context.Background()
	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T) {
			version, err := tc.container.Last(ctx)
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

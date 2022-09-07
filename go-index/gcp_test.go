package index

import (
	"context"
	"errors"
	"net/http"
	"testing"
)

func TestGCP_Match(t *testing.T) {
	tt := []struct {
		name       string
		gcp        GCP
		opts       FilterOpts
		wantedName string
		wantError  error
	}{
		{
			name: "valid",
			gcp: GCP{
				GCPIndex: nil,
				Fetcher: &GCPIndexFetchMock{
					GetImagesFunc: func(ctx context.Context, opts FilterOpts) (GCPImages, error) {
						return GCPImages{
							GCPImage{
								Labels: struct {
									CalyptiaCoreRelease string `json:"calyptia-core-release"`
									SourceImage         string `json:"source-image"`
								}{
									CalyptiaCoreRelease: "0-2-6",
								},
								Name:             "test",
								StorageLocations: []string{"us"},
							},
						}, nil
					},
				},
			},
			opts: FilterOpts{
				Region:    "us",
				Version:   "v0.2.6",
				TestIndex: false,
			},
			wantedName: "test",
		},
		{
			name: "not found in index",
			gcp: GCP{
				GCPIndex: nil,
				Fetcher: &GCPIndexFetchMock{
					GetImagesFunc: func(ctx context.Context, opts FilterOpts) (GCPImages, error) {
						return GCPImages{
							GCPImage{
								Labels: struct {
									CalyptiaCoreRelease string `json:"calyptia-core-release"`
									SourceImage         string `json:"source-image"`
								}{
									CalyptiaCoreRelease: "0-2-5",
								},
								StorageLocations: []string{"us"},
							},
						}, nil
					},
				},
			},
			opts: FilterOpts{
				Region:    "us",
				Version:   "v0.2.6",
				TestIndex: false,
			},
			wantError: ErrNoMatchingImage,
		},
		{
			name: "error getting images",
			gcp: GCP{
				GCPIndex: nil,
				Fetcher: &GCPIndexFetchMock{
					GetImagesFunc: func(ctx context.Context, opts FilterOpts) (GCPImages, error) {
						return nil, http.ErrHijacked
					},
				},
			},
			opts: FilterOpts{
				Region:    "us",
				Version:   "v0.2.6",
				TestIndex: false,
			},
			wantError: http.ErrHijacked,
		},
	}

	ctx := context.Background()

	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T) {
			version, err := tc.gcp.Match(ctx, tc.opts)
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

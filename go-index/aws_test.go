package index

import (
	"context"
	"errors"
	_ "errors"
	"net/http"
	"testing"
	"time"
)

func TestAWS_Match(t *testing.T) {
	tt := []struct {
		name       string
		aws        AWS
		version    string
		wantedName string
		wantError  error
	}{
		{
			name: "valid",
			aws: AWS{
				Fetcher: &AWSIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (AWSImages, error) {
						return AWSImages{
							AWSImage{
								ImageID: "test",
								Name:    "test",
								Tags: []struct {
									Key   string `json:"Key"`
									Value string `json:"Value"`
								}{
									{
										Key:   awsCoreReleaseTag,
										Value: "0.2.6",
									},
								},
							},
						}, nil
					},
				},
			},
			version:    "v0.2.6",
			wantedName: "test",
		},
		{
			name: "valid with multiple matching, get last one",
			aws: AWS{
				Fetcher: &AWSIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (AWSImages, error) {
						return AWSImages{
							AWSImage{
								CreationDate: time.Now().String(),
								ImageID:      "first",
								Name:         "first",
								Tags: []struct {
									Key   string `json:"Key"`
									Value string `json:"Value"`
								}{
									{
										Key:   awsCoreReleaseTag,
										Value: "0.2.6",
									},
								},
							},
							AWSImage{
								CreationDate: time.Now().Add(time.Minute).String(),
								ImageID:      "last-image",
								Name:         "last-image",
								Tags: []struct {
									Key   string `json:"Key"`
									Value string `json:"Value"`
								}{
									{
										Key:   awsCoreReleaseTag,
										Value: "0.2.6",
									},
								},
							},
						}, nil
					},
				},
			},
			version:    "v0.2.6",
			wantedName: "last-image",
		},
		{
			name: "not found in index",
			aws: AWS{
				Fetcher: &AWSIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (AWSImages, error) {
						return AWSImages{
							AWSImage{
								ImageID: "test",
								Name:    "test",
								Tags: []struct {
									Key   string `json:"Key"`
									Value string `json:"Value"`
								}{
									{
										Key:   awsCoreReleaseTag,
										Value: "0.2.5",
									},
								},
							},
						}, nil
					},
				},
			},
			version:   "v0.2.6",
			wantError: ErrNoMatchingImage,
		},
		{
			name: "error getting images",
			aws: AWS{
				Fetcher: &AWSIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (AWSImages, error) {
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
			version, err := tc.aws.Match(ctx, tc.version)
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

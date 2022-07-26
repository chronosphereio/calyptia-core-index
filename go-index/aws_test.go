package index

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"
)

func TestAWS_Match(t *testing.T) {
	tt := []struct {
		name       string
		aws        AWS
		version    string
		region     string
		wantedName string
		wantError  error
	}{
		{
			name:   "valid",
			region: "us-east-1",
			aws: AWS{
				Fetcher: &AWSIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (AWSImages, error) {
						return AWSImages{
							AWSImage{
								ImageID: "test",
								Name:    "test",
								Region:  "us-east-1",
								Release: "0.2.6",
							},
						}, nil
					},
				},
			},
			version:    "v0.2.6",
			wantedName: "test",
		},
		{
			name: "not matching",
			aws: AWS{
				Fetcher: &AWSIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (AWSImages, error) {
						return AWSImages{
							AWSImage{
								CreationDate: time.Now(),
								ImageID:      "first",
								Name:         "first",
								Release:      "0.2.7",
								Region:       "us-west-1",
							},
							AWSImage{
								CreationDate: time.Now().Add(time.Minute),
								ImageID:      "last-image",
								Name:         "last-image",
								Release:      "0.2.8",
								Region:       "us-west-1",
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
			version, err := tc.aws.Match(ctx, tc.region, tc.version)
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

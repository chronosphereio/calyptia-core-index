package index

import (
	"errors"
	_ "errors"
	"net/http"
	"testing"
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
					GetImagesFunc: func() (AWSImages, error) {
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
			name: "not found in index",
			aws: AWS{
				Fetcher: &AWSIndexFetchMock{
					GetImagesFunc: func() (AWSImages, error) {
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
					GetImagesFunc: func() (AWSImages, error) {
						return nil, http.ErrHijacked
					},
				},
			},
			version:   "v0.2.6",
			wantError: http.ErrHijacked,
		},
	}

	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T) {
			version, err := tc.aws.Match(tc.version)
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

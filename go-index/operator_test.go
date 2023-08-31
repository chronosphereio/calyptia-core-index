package index

import (
	"context"
	"errors"
	"net/http"
	"reflect"
	"testing"
)

func TestOperator_Match(t *testing.T) {
	tt := []struct {
		name       string
		operator   Operator
		version    string
		wantedName string
		wantError  error
	}{
		{
			name: "valid",
			operator: Operator{
				Fetcher: &OperatorIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (OperatorImages, error) {
						return OperatorImages{
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
			operator: Operator{
				Fetcher: &OperatorIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (OperatorImages, error) {
						return OperatorImages{
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
			operator: Operator{
				Fetcher: &OperatorIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (OperatorImages, error) {
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
			version, err := tc.operator.Match(ctx, tc.version)
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

func TestOperator_All(t *testing.T) {
	tt := []struct {
		name           string
		operator       Operator
		wantedVersions []string
		wantError      error
	}{
		{
			name: "valid",
			operator: Operator{
				OperatorIndex: nil,
				Fetcher: &OperatorIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (OperatorImages, error) {
						return OperatorImages{
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
			wantedVersions: OperatorImages{
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
			operator: Operator{
				OperatorIndex: nil,
				Fetcher: &OperatorIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (OperatorImages, error) {
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
			versions, err := tc.operator.All(ctx)
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

func TestOperator_Last(t *testing.T) {
	tt := []struct {
		name          string
		operator      Operator
		wantedVersion string
		wantError     error
	}{
		{
			name: "valid",
			operator: Operator{
				OperatorIndex: nil,
				Fetcher: &OperatorIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (OperatorImages, error) {
						return OperatorImages{
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
			operator: Operator{
				OperatorIndex: nil,
				Fetcher: &OperatorIndexFetchMock{
					GetImagesFunc: func(ctx context.Context) (OperatorImages, error) {
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
			version, err := tc.operator.Last(ctx)
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

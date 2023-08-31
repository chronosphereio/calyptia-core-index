// Code generated by moq; DO NOT EDIT.
// github.com/matryer/moq

package index

import (
	"context"
	"sync"
)

// Ensure, that OperatorIndexFetchMock does implement OperatorIndexFetch.
// If this is not the case, regenerate this file with moq.
var _ OperatorIndexFetch = &OperatorIndexFetchMock{}

// OperatorIndexFetchMock is a mock implementation of OperatorIndexFetch.
//
//	func TestSomethingThatUsesOperatorIndexFetch(t *testing.T) {
//
//		// make and configure a mocked OperatorIndexFetch
//		mockedOperatorIndexFetch := &OperatorIndexFetchMock{
//			GetImagesFunc: func(ctx context.Context) (OperatorImages, error) {
//				panic("mock out the GetImages method")
//			},
//		}
//
//		// use mockedOperatorIndexFetch in code that requires OperatorIndexFetch
//		// and then make assertions.
//
//	}
type OperatorIndexFetchMock struct {
	// GetImagesFunc mocks the GetImages method.
	GetImagesFunc func(ctx context.Context) (OperatorImages, error)

	// calls tracks calls to the methods.
	calls struct {
		// GetImages holds details about calls to the GetImages method.
		GetImages []struct {
			// Ctx is the ctx argument value.
			Ctx context.Context
		}
	}
	lockGetImages sync.RWMutex
}

// GetImages calls GetImagesFunc.
func (mock *OperatorIndexFetchMock) GetImages(ctx context.Context) (OperatorImages, error) {
	if mock.GetImagesFunc == nil {
		panic("OperatorIndexFetchMock.GetImagesFunc: method is nil but OperatorIndexFetch.GetImages was just called")
	}
	callInfo := struct {
		Ctx context.Context
	}{
		Ctx: ctx,
	}
	mock.lockGetImages.Lock()
	mock.calls.GetImages = append(mock.calls.GetImages, callInfo)
	mock.lockGetImages.Unlock()
	return mock.GetImagesFunc(ctx)
}

// GetImagesCalls gets all the calls that were made to GetImages.
// Check the length with:
//
//	len(mockedOperatorIndexFetch.GetImagesCalls())
func (mock *OperatorIndexFetchMock) GetImagesCalls() []struct {
	Ctx context.Context
} {
	var calls []struct {
		Ctx context.Context
	}
	mock.lockGetImages.RLock()
	calls = mock.calls.GetImages
	mock.lockGetImages.RUnlock()
	return calls
}

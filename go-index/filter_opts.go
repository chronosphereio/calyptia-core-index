package index

// FilterOpts those are the options available to filter the images from the index.
type FilterOpts struct {
	// i.e us-east-1
	Region string
	// i.e 0.2.9
	Version string
	// Determine if use the test index, default false.
	TestIndex bool
}

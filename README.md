# Calyptia Core - Public image indexes and other tooling

This is a public repository to an updated set of indexes of container tags and public cloud provider images.

The following index files of supported images for [Calyptia Core](https://calyptia.com/products/calyptia-core/).

| Index file                                          | Description                                                        |
|-----------------------------------------------------|--------------------------------------------------------------------|
| [Container images index](./container.index.json) | List of tags available on the container registry for Calyptia Core. |
| [Core Fluent Bit JSON schemas](./schemas/) | The JSON schemas for Calyptia Core Fluent Bit versions. |
| [AWS VM images index](./aws.index.json)  | List of AWS VM images available. |
| [GCP VM images index](./gcp.index.json)  | List of GCP VM images available. |
| [Packer VM manifest](./packer-manifest.json) | The manifest from the latest Packer build. |

## Install Calyptia Core

We provide a simple helper script to install Calyptia Core on various supported platforms like so:

```shell
curl -sSfL https://raw.githubusercontent.com/calyptia/core-images-index/main/install-core.sh | sudo sh -s -
```

This will run pre-flight checks which you can force install afterwards with a `--force` parameter:

```shell
$ curl -sSfL https://raw.githubusercontent.com/calyptia/core-images-index/main/install-core.sh | sudo sh -s - --force
[INFO]   =================================== 
[INFO]    Calyptia Core Installation Script  
[INFO]   =================================== 
[INFO]   This script requires superuser access to install packages. 
[INFO]   You will be prompted for your password by sudo. 
[INFO]   =================================== 
[INFO]   Detected: centos, amd64 
[INFO]   Installing Calyptia Core 0.4.6 to: /opt/calyptia-core 
[INFO]   Installing Calyptia CLI 0.48.0 
[INFO]   Installing as root:root 
[WARN]   Ignoring any errors during preflight checks 
```

## "Public" images

For the clouds there is no concept of "public" images, the closest is an image that any authenticated user can use.

As part of the Packer build, we set this up automatically for AWS: <https://www.packer.io/plugins/builders/amazon/ebs#ami_groups>.

For GCP, the way to do this is documented here: <https://cloud.google.com/compute/docs/images/managing-access-custom-images#share-images-publicly>.

To add permissions for a specific image, it is fairly simple once authenticated as a user or account with appropriate permissions to modify the image in that way:

```shell
gcloud compute images add-iam-policy-binding "$IMAGE_NAME" \
    --member='allAuthenticatedUsers' \
    --role='roles/compute.imageUser'
```

You can check whether an image is public by confirming it has that role for `allAuthenticatedUsers`, for example:

```shell
$ gcloud compute images get-iam-policy https://www.googleapis.com/compute/v1/projects/calyptia-infra/global/images/calyptia-core-benchmark-ubuntu-2004
bindings:
- members:
  - allAuthenticatedUsers
  role: roles/compute.imageUser
etag: BwXmlbh2nkQ=
version: 1
```

Make sure to use the full URL for the image whenever you reference it as shown above.
You cannot use an image family or other options without relevant permissions to list images on the specific project the image is in.

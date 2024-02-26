# Calyptia Core - Public image indexes and other tooling

This is a public repository to an updated set of indexes of container tags.

The following index files of supported images for [Calyptia Core](https://calyptia.com/products/calyptia-core/).

| Index file                                          | Description                                                        |
|-----------------------------------------------------|--------------------------------------------------------------------|
| [Container images index](./container.index.json) | List of tags available on the container registry for Calyptia Core. |
| [Core Fluent Bit JSON schemas](./schemas/) | The JSON schemas for Calyptia Core Fluent Bit versions. |

## Install Calyptia Core

We provide a simple helper script to install Calyptia Core on various supported platforms like so:

```shell
curl -sSfL https://raw.githubusercontent.com/chronosphereio/calyptia-core-index/main/install-core.sh | bash -s -
```

This will run pre-flight checks which you can force install afterwards with a `--force` parameter:

```shell
$ curl -sSfL https://raw.githubusercontent.com/chronosphereio/calyptia-core-index/main/install-core.sh | bash -s - --force
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

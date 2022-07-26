
#!/bin/bash
set -u

IMAGE_KEY=${IMAGE_KEY:-calyptia-core-release}
AWS_INDEX_FILE=${AWS_INDEX_FILE:-aws.index.json}

# Assumption for GCP is authentication is complete prior to this script
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:?}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:?}

# For AWS we have to iterate over regions
for aws_region in $(aws ec2 describe-regions --output text | cut -f4)
do
    # As we only want a single image per tag value we need to first get our tag values then query for each one and take the latest
    aws ec2 describe-tags --no-paginate --region "$aws_region" \
        --filter "Name=key,Values=calyptia-core-release" --query 'Tags[*]' --output json | jq -cr 'unique_by(.Key,.Value)|.[].Value' > "$aws_region".tags

    # Get our images with this tag value and region, sort by creation date and select last for most recent then add region + release info
    while IFS= read -r release_tag_value; do
        aws ec2 describe-images --no-paginate --owners self --region "$aws_region" \
            --filters "Name=tag:$IMAGE_KEY,Values=$release_tag_value" "Name=name,Values=gold-calyptia-core*" \
            --query 'Images[] | sort_by(@, &CreationDate)[].{CreationDate: CreationDate, ImageId: ImageId, Name: Name, Tags: Tags}|[-1]' \
            --output=json | jq ". += {\"region\" : \"$aws_region\", \"release\": \"$release_tag_value\" }" > aws-region-"$aws_region"-"$release_tag_value".json
    done <"$aws_region".tags
    rm -f "$aws_region".tags
done

# Now combine our region files into a single array
jq -s . aws-region-*.json | tee "$AWS_INDEX_FILE"
rm -f aws-region-*.json

#!/usr/bin/env python

"""
Script to generate EC2 instance template using the latest definition
"""

from __future__ import annotations

import json
import sys
from os import path

import requests
from troposphere import (
    Condition,
    Not,
    Equals,
    FindInMap,
    GetAtt,
    Parameter,
    Ref,
    Region,
    Sub,
    Template,
    Base64,
    Join,
    If
)
from troposphere.ec2 import Instance, SecurityGroup
from troposphere.iam import Role, InstanceProfile, PolicyType


def get_latest_definition_from_url(src_url: str) -> list[dict]:
    """Get index definition from URL"""
    index_content = requests.get(src_url).json()
    for image in index_content:
        del image["Tags"]
    return index_content


def get_definition_from_file(src_path: str) -> list[dict]:
    """Reads the index file and returns it after JSON parsing"""
    with open(path.abspath(src_path), "r") as index_fd:
        content = index_fd.read()
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        print("Failed to import JSON index")
        raise


def create_mapping(calyptia_images_index: list[dict]) -> dict:
    """Creates CFN mapping per region per version"""
    regions_mappings: dict = {}
    for image_def in calyptia_images_index:
        _region = image_def["region"]
        if _region not in regions_mappings:
            _region_dict: dict = {}
            regions_mappings[_region] = _region_dict
        else:
            _region_dict = regions_mappings[_region]

        _release_version = image_def["release"].replace(".", "")
        if _release_version not in _region_dict:
            _region_dict[_release_version] = image_def["ImageId"]

    return regions_mappings


def create_template(amis_mapping: dict) -> Template:
    """Creates the CFN Template"""
    allowed_versions: list[str] = []
    for _region, _versions in amis_mapping.items():
        for _version in _versions:
            if _version not in allowed_versions:
                allowed_versions.append(_version)

    template = Template("EC2 Instance with Fluent-Bit by Calyptia")
    template.add_mapping("RegionsAmis", amis_mapping)
    version_id = template.add_parameter(
        Parameter("Version", Type="String", AllowedValues=allowed_versions)
    )
    permissions_boundary = template.add_parameter(
        Parameter(
            "IamPermissionsBoundary",
            Type="String",
            Description="Optional - IamPermissionsBoundary for Instance Role",
            Default="none",
        )
    )
    template.add_condition(
        "UsePermissionsBoundary", Not(Equals(Ref(permissions_boundary), "none"))
    )
    vpc_id = template.add_parameter(Parameter("VpcId", Type="AWS::EC2::VPC::Id"))
    subnet = template.add_parameter(Parameter("SubnetId", Type="AWS::EC2::Subnet::Id"))
    instance_sg = template.add_resource(
        SecurityGroup(
            "InstanceSecurityGroup",
            GroupDescription=Sub("${AWS::StackName} - CalyptiaCore"),
            VpcId=Ref(vpc_id),
        )
    )
    iam_role = template.add_resource(
        Role(
            "InstanceRole",
            PermissionsBoundary=If("UsePermissionsBoundary", Ref(permissions_boundary), Ref("AWS::NoValue")),
            ManagedPolicyArns=[
                "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
            ],
            Description=Sub("${AWS::StackName} - FluentBit getting-started"),
            AssumeRolePolicyDocument={
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {"Service": [Sub("ec2.${AWS::URLSuffix}")]},
                        "Action": ["sts:AssumeRole"],
                    }
                ],
            },
        )
    )

    instance_profile = template.add_resource(
        InstanceProfile(
            f"IamInstanceProfile", Roles=[Ref(iam_role)], DependsOn=[iam_role.title]
        )
    )
    instance = template.add_resource(
        Instance(
            "CalyptiaCore",
            DependsOn=[
                iam_role.title,
                instance_profile.title,
            ],
            ImageId=FindInMap("RegionsAmis", Region, Ref(version_id)),
            SubnetId=Ref(subnet),
            SecurityGroups=[GetAtt(instance_sg, "GroupId")],
            IamInstanceProfile=Ref(instance_profile),
            UserData=Base64(
                """#!/bin/bash
                mkdir /tmp/ssm
                cd /tmp/ssm
                wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
                sudo dpkg -i amazon-ssm-agent.deb
                sudo systemctl enable amazon-ssm-agent
                """
            ),
        )
    )
    return template


def render_template(mappings: dict, output_path: str) -> None:
    """Generates template, validates if possible, writes to file"""
    template = create_template(mappings)
    try:
        import boto3

        cfn = boto3.client("cloudformation")
        cfn.validate_template(TemplateBody=template.to_json())
    except Exception as error:
        print(error)
    with open(path.abspath(output_path), "w") as template_fd:
        template_fd.write(template.to_yaml())


def main():
    from argparse import ArgumentParser

    parser = ArgumentParser("Generate demo EC2 template for Core")
    parser.add_argument("-f", "--file", help="Path to the index file", type=str)
    parser.add_argument(
        "--url",
        help="URL to the images index",
        default="https://raw.githubusercontent.com/calyptia/core-images-index/main/aws.index.json",
    )
    parser.add_argument(
        "-o", "--output", help="Output template path", type=str, default="calyptia.yaml"
    )

    args = parser.parse_args()
    if args.file:
        mappings = create_mapping(get_definition_from_file(args.file))
    else:
        mappings = create_mapping(get_latest_definition_from_url(args.url))
    render_template(mappings, args.output)


if __name__ == "__main__":
    sys.exit(main())

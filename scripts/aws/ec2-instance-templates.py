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
from troposphere.ec2 import Instance, SecurityGroup, SecurityGroupRule
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
        if not _release_version.startswith("0"):
            if _release_version not in _region_dict:
                _region_dict[_release_version] = image_def["ImageId"]

    return regions_mappings


def create_ssm_template(amis_mapping: dict) -> Template:
    """Creates the CFN Template"""
    allowed_versions: list[str] = []
    for _region, _versions in amis_mapping.items():
        for _version in _versions:
            if _version not in allowed_versions:
                allowed_versions.append(_version)

    template = Template("Calyptia Core EC2 Instance")
    template.add_mapping("RegionsAmis", amis_mapping)
    version_id = template.add_parameter(
        Parameter("Version", Type="String", AllowedValues=allowed_versions)
    )
    project_token = template.add_parameter(
        Parameter("CalyptiaCoreToken", Type="String")
    )
    instance_type = template.add_parameter(
        Parameter("InstanceType", Type="String")
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
        "UsePermissionsBoundary", Not(
            Equals(Ref(permissions_boundary), "none"))
    )
    vpc_id = template.add_parameter(
        Parameter("VpcId", Type="AWS::EC2::VPC::Id"))
    subnet = template.add_parameter(
        Parameter("SubnetId", Type="AWS::EC2::Subnet::Id"))
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
            PermissionsBoundary=If("UsePermissionsBoundary", Ref(
                permissions_boundary), Ref("AWS::NoValue")),
            ManagedPolicyArns=[
                "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
            ],
            Description=Sub("${AWS::StackName} - Calyptia Core"),
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
            InstanceType=Ref(instance_type),
            SubnetId=Ref(subnet),
            SecurityGroupIds=[GetAtt(instance_sg, "GroupId")],
            IamInstanceProfile=Ref(instance_profile),
            UserData=Base64(
                Join("=", ["CALYPTIA_CLOUD_PROJECT_TOKEN", Ref(project_token)])),
        )
    )
    return template


def create_ssh_template(amis_mapping: dict) -> Template:
    """Creates the CFN Template"""
    allowed_versions: list[str] = []
    for _region, _versions in amis_mapping.items():
        for _version in _versions:
            if _version not in allowed_versions:
                allowed_versions.append(_version)

    template = Template("Calyptia Core EC2 Instance with SSH access")
    template.add_mapping("RegionsAmis", amis_mapping)
    version_id = template.add_parameter(
        Parameter("Version", Type="String", AllowedValues=allowed_versions)
    )
    project_token = template.add_parameter(
        Parameter("CalyptiaCoreToken", Type="String")
    )
    instance_type = template.add_parameter(
        Parameter("InstanceType", Type="String")
    )
    ssh_location = template.add_parameter(
        Parameter("SSHLocation", Type="String", MinLength=9,
                  MaxLength=18, Default="0.0.0.0/0")
    )
    key_name = template.add_parameter(
        Parameter("KeyName", Type="AWS::EC2::KeyPair::KeyName",
                  ConstraintDescription="Must be the name of an existing EC2 KeyPair.")
    )

    instance_sg = template.add_resource(
        SecurityGroup(
            "InstanceSecurityGroup",
            GroupDescription=Sub("${AWS::StackName} - CalyptiaCore"),
            SecurityGroupIngress=[
                SecurityGroupRule(
                    IpProtocol="tcp",
                    FromPort=22,
                    ToPort=22,
                    CidrIp=Ref(ssh_location),
                ),
            ]
        )
    )

    instance = template.add_resource(
        Instance(
            "CalyptiaCore",
            ImageId=FindInMap("RegionsAmis", Region, Ref(version_id)),
            InstanceType=Ref(instance_type),
            SecurityGroupIds=[GetAtt(instance_sg, "GroupId")],
            KeyName=Ref(key_name),
            UserData=Base64(
                Join("=", ["CALYPTIA_CLOUD_PROJECT_TOKEN", Ref(project_token)])),
        )
    )
    return template


def render_ssm_template(mappings: dict, output_path: str) -> None:
    """Generates template, validates if possible, writes to file"""
    template = create_ssm_template(mappings)
    try:
        import boto3

        cfn = boto3.client("cloudformation")
        cfn.validate_template(TemplateBody=template.to_json())
    except Exception as error:
        print(error)
    with open(path.abspath(output_path), "w") as template_fd:
        template_fd.write(template.to_yaml())


def render_ssh_template(mappings: dict, output_path: str) -> None:
    """Generates template, validates if possible, writes to file"""
    template = create_ssh_template(mappings)
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

    parser = ArgumentParser("Generate EC2 template for Calyptia Core")
    parser.add_argument(
        "-f", "--file", help="Path to the index file", type=str)
    parser.add_argument(
        "--url",
        help="URL to the images index",
        default="https://raw.githubusercontent.com/calyptia/core-images-index/main/aws.index.json",
    )
    parser.add_argument(
        "--outputssm", help="Output SSM template path", type=str, default="calyptia-ssm.yaml"
    )
    parser.add_argument(
        "--outputssh", help="Output SSH template path", type=str, default="calyptia-ssh.yaml"
    )

    args = parser.parse_args()
    if args.file:
        mappings = create_mapping(get_definition_from_file(args.file))
    else:
        mappings = create_mapping(get_latest_definition_from_url(args.url))
    render_ssm_template(mappings, args.outputssm)
    render_ssh_template(mappings, args.outputssh)


if __name__ == "__main__":
    sys.exit(main())

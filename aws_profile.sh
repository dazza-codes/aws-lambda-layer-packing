#!/bin/bash
# Copyright 2020 Darren Weber
# 
# Licensed under the Apache License, Version 2.0 (the "License"). You may not
# use this file except in compliance with the License. A copy of the License is
# located at
# 
#      http://aws.amazon.com/apache2.0/
# 
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions
# and limitations under the License.

#   FILE:  aws_profile.sh
# 
#   USAGE:  ./aws_profile.sh [profile-name | clear]
# 
#   DESCRIPTION:  Bash function to list or activate AWS credentials from profile
#   names, see also:
#                 
#   - https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
#   - https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html
# 
#   Source this script file in ~/.bashrc to have the function
#   available in the current shell, where it can modify the env.


aws-profile () {
    profile_name=${1:-default}
    if grep -q "\[${profile_name}\]" ~/.aws/credentials; then
        export AWS_DEFAULT_PROFILE="${profile_name}"
        export AWS_DEFAULT_REGION=$(aws configure --profile $AWS_DEFAULT_PROFILE get region)
        export AWS_ACCOUNT=$(aws sts get-caller-identity | grep 'Account' | sed 's/[^0-9]//g')
        export AWS_ACCESS_KEY_ID=$(aws configure --profile $AWS_DEFAULT_PROFILE get aws_access_key_id)
        export AWS_SECRET_ACCESS_KEY=$(aws configure --profile $AWS_DEFAULT_PROFILE get aws_secret_access_key)
        export TF_VAR_aws_default_profile="${profile_name}"  # for terraform
    elif [ "$profile_name" == "clear" ]; then
        echo "WARNING: clearing profile settings"
        unset AWS_DEFAULT_PROFILE
        unset AWS_DEFAULT_REGION
        unset AWS_ACCOUNT
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        unset TF_VAR_aws_default_profile
    else
        echo "WARNING: ${profile_name} is not available"
        echo "Available profiles:"
        sed -n -e 's/^\[\(.*\)\]$/\1/p' ~/.aws/credentials
        echo "'clear' will unset any current active profile"
        echo "'default' is used when no profile is specified"
    fi
    echo
    echo "AWS_DEFAULT_PROFILE=${AWS_DEFAULT_PROFILE}"
    echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
    echo
}


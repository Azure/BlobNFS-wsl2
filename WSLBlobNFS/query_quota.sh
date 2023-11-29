#!/bin/bash

# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------

# Query the quota of the NFSv3 share. Since NFSv3 shares don't support quotas, this script will return 0.
# 3 arguments to the script:
# 1. directory
# 2. type of query
# 3. uid of user or gid of group
#
# The directory is actually mostly just "." - It needs to be treated relatively to the current working directory that
# the script can also query.
# The type of query can be one of:
# 1 - user quotas
# 2 - user default quotas (uid = -1)
# 3 - group quotas
# 4 - group default quotas (gid = -1)
#
# This script should print one line as output with spaces between the columns. The printed columns should be:
# 1 - quota flags (0 = no quotas, 1 = quotas enabled, 2 = quotas enabled and enforced)
# 2 - number of currently used blocks
# 3 - the softlimit number of blocks
# 4 - the hardlimit number of blocks
# 5 - currently used number of inodes
# 6 - the softlimit number of inodes
# 7 - the hardlimit number of inodes
# 8 (optional) - the number of bytes in a block(default is 1024)

# Usage Example: get quota command = /usr/local/sbin/query_quota

# To-do: Check if directory is a Blob NFSv3 mount
echo "0 0 0 0 0 0 0 1024"

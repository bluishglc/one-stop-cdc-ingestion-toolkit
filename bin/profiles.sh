#!/bin/bash
# a profile contains a copy of VPC, MSK Cluster and multiple MSK Connectors configurations.
# With multiple profiles, we can support multiple msk clusters.
# It is not a good idea to maintain many-to-many relationship between MSK Cluster and MSK Connectors
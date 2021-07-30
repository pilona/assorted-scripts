#! /bin/sh

# Finds all GKE clusters in GCP and sets up kubectl.
# The context names are a tad annoying though.
# Also finds all Cloud Run services, and sets up a kubectl context named

set -e

organization="$(gcloud organizations list --limit=1 --format='value(ID)')"

# Assumes that this will all be returned in one page. Good enough for now.

clusters() {
    gcloud asset search-all-resources \
        --filter 'assetType="container.googleapis.com/Cluster"' \
        --scope organizations/"$organization" \
        --format 'table[no-header](name)' \
      | while IFS=/ read -r foo bar api projects project zones zone clusters cluster rest; do
            if [ "$api" != container.googleapis.com ] || \
               [ "$projects" != projects ] || \
               [ "$zones" != zones -a "$zones" != locations ]; then
                printf 'Malformed input: %s %s %s %s %s %s %s %s %s %s\n' \
                    "$foo" "$bar" "$api" "$projects" "$project" "$zones" \
                    "$zone" "$clusters" "$cluster" "$rest" \
                    1>&2
                continue
            fi
            #region="$(echo "$zone" | cut -d - -f 1-2)"
            echo gcloud container clusters get-credentials "$cluster" \
              --region="$zone" --project "$project"
        done
}

# This breaks abstraction, both in mapping Cloud Run to Knative and how gcloud
# named the user in a context above, will set up the same context multiple time
# if multiple services per project, but whatever.
cloud_runs() {
    user="$(kubectl config get-contexts -o=name | grep '^gke_' | head -n 1)"
    gcloud asset search-all-resources \
        --filter 'assetType="run.googleapis.com/Service"' \
        --scope organizations/"$organization" \
        --format 'table[no-header](name)' \
      | while IFS=/ read -r foo bar api projects project zones zone clusters cluster rest; do
            if [ "$api" != run.googleapis.com ] || \
               [ "$projects" != projects ] || \
               [ "$zones" != zones -a "$zones" != locations ]; then
                printf 'Malformed input: %s %s %s %s %s %s %s %s %s %s\n' \
                    "$foo" "$bar" "$api" "$projects" "$project" "$zones" \
                    "$zone" "$clusters" "$cluster" "$rest" \
                    1>&2
                continue
            fi
            knative_server="https://$zone-run.googleapis.com:443"
            ca_certificates="$(curl-config --ca)"
            kubectl config set-cluster "$project"-run \
               --server="$knative_server" \
               --certificate-authority="$ca_certificates"
            kubectl config set-context "$project"-run \
                --cluster="$project"-run \
                --namespace="$project" \
                --user="$user"
        done
}

clusters
cloud_runs

# PostgreSQL extensions as image volumes with CloudNativePG

Demo for the talk *PostgreSQL Extensions as Image Volumes: Decoupling Extensions from the
Operand Image with CloudNativePG*.

A custom operand image has been the usual way to add an extension to PostgreSQL on Kubernetes.
PostgreSQL 18 added `extension_control_path`, and Kubernetes can mount an OCI image as a
read-only volume (`ImageVolume`). CloudNativePG (CNPG) combines the two: the extension ships as
its own small image, and the operator mounts it under `/extensions/<name>` and adds the paths to
`extension_control_path` and `dynamic_library_path`.

This repository runs that on a 3-instance cluster with
[`edb_wait_states`](https://www.enterprisedb.com/docs/pg_extensions/wait_states/), then exposes
the wait events it samples as a custom CNPG metric. The metric query is gated by
`predicate_query`, so the series only exists once the extension is created and sessions are
waiting on something.

> **An EDB subscription token is required.** The extension image is built from the
> `edb_wait_states` package in the EDB repositories, which need a token. Without it the demo
> cannot build the extension image. On kind the image is built locally and loaded into the
> cluster; on OpenShift it is built in the cluster. See [EDB token](#edb-token).

## What the demo shows

| Step | Command | What happens |
| --- | --- | --- |
| Baseline | `make baseline`, `make show-baseline` | A minimal PG 18 cluster. `CREATE EXTENSION edb_wait_states` fails, and the metric is absent from Prometheus. |
| Diff | `make diff-extension` | The YAML change: `shared_preload_libraries` and an `extensions` entry. |
| Add | `make add-extension` | One rolling update. |
| Wiring | `make show-wiring` | The mount under `/extensions/edb-wait-states`, the two paths the operator sets, and the preload setting. |
| Create | `make database` | A declarative `Database` resource runs `CREATE EXTENSION`. |
| Load | `make load` | About 15 s of sessions waiting in `pg_sleep`, so there are wait events to sample. |
| Metric | `make show-metric` | `cnpg_edb_wait_states_samples{wait_event_type, wait_event}` appears in Prometheus (for example `Timeout` / `PgSleep`). |

`make smoke` runs the demo steps end to end and asserts each result.

## Requirements

An EDB subscription token (see [EDB token](#edb-token)).

Common: `curl` and a Kubernetes client. The client must be within one minor version of the
server (`oc` on OpenShift). Set `KUBECTL` to force a specific binary. Docker and `buildx`
are needed only for kind; OpenShift builds the extension image in the cluster and needs none of them.

| Environment | Needs |
| --- | --- |
| kind | `kind` and Docker. The scripts create the cluster, install CNPG 1.30.1 (chart 0.29.1) and a Prometheus Operator with one Prometheus. |
| Existing cluster (for example OpenShift 4.22) | Kubernetes 1.35 or later (or the `ImageVolume` gate on 1.33 and 1.34) with a runtime that supports image volumes, CNPG 1.30 or later, and a Prometheus that scrapes `PodMonitor`s in the demo namespace. On OpenShift the scripts read CRDs and operator deployments cluster-wide and exec into the user-workload Prometheus pod, so run them as a cluster admin. |

```bash
make prereqs
```

### EDB token

The extension image installs `postgresql18-edb-wait-states` from the EDB repositories with
your EDB subscription token. Put it in a `.env` file at the repository root (git-ignored):

```bash
cp .env.example .env    # then set EDB_SUBSCRIPTION_TOKEN=<your token>
```

`make build-image` (and `make setup`, `make setup-kind`) read it, or take it from the
environment. On kind it goes to a local `docker buildx build`; on OpenShift to an in-cluster
binary build (BuildConfig `edbws`). In both it sits in a temporary build context and is copied
into the builder stage only, which the final `FROM scratch` image does not include, so it is
not in the image or its layers. `make verify` warns when it is missing.

The package is built for community PostgreSQL 18 on Debian trixie, so it runs in the plain
`ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie` image. The Dockerfile pins it with the
build argument `EXT_VERSION` (1.7.0-1.trixie).

### OpenShift

Install CloudNativePG from OperatorHub. The platform Prometheus does not scrape user
namespaces, so enable user-workload monitoring once, as a cluster admin, by creating this
ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
```

If a `cluster-monitoring-config` ConfigMap already exists, add `enableUserWorkload: true` to its
`config.yaml` instead of replacing it. The setting applies to the whole cluster. With a Prometheus
Operator instance instead, its `podMonitorSelector` and `podMonitorNamespaceSelector` must select
the demo `PodMonitor`, which has no labels, in the demo namespace.

`make verify` checks all of this and prints the fix for anything missing.

## Usage

### kind

```bash
make setup-kind     # cluster, operator, Prometheus, image, verify, baseline
make smoke          # optional: the whole demo with assertions
make kind-down      # delete the kind cluster
```

`setup-kind` switches your kubectl context to `kind-cnpg-imgvol`.

### Existing cluster

```bash
make verify         # preconditions on the current context (creates the demo namespace)
make setup          # build the image, verify, deploy the baseline
make smoke
make teardown       # deletes only the demo namespace, and only if this repo created it
```

The image build step has a backend for kind and OpenShift only. On any other cluster, build the
image from `docker/edb-wait-states/Dockerfile` (put your token in a file named
`edb-subscription-token` next to it for the build), push it to a registry the cluster can pull
from, and set `EXT_IMAGE` to its reference. The build step then
builds nothing.

Scripts act on the current context and print the target context, server and namespace before
they write. They only use a namespace that carries this repo's label, and stop without touching
any other. To target another context without switching yours:

```bash
KUBE_CONTEXT=<context> make verify
```

### Demo

Run the commands from the table above in order. `make reset` goes back to the baseline at any
time and keeps the built image: it removes the demo cluster and `Database`, then redeploys the
baseline.

Prometheus UI: on kind,
`kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090`. On OpenShift,
Observe, then Metrics, with the project set to `cnpg-imgvol-demo`. Query
`cnpg_edb_wait_states_samples`, right after `make load`: the metric counts the samples of the last
5 minutes, so the series disappears about 5 minutes after the load ends.

## License

See [LICENSE](LICENSE).

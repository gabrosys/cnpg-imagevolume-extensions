# Extension image for CloudNativePG image volumes: only the files PostgreSQL needs,
# in the layout the operator expects (/lib, /share, /licenses).
ARG BASE=ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
FROM $BASE AS builder

ARG PG_MAJOR=18
ARG EXT_VERSION=1.7.0-1.trixie

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER 0

COPY edb-subscription-token /tmp/edb-subscription-token

# The token is in the repository URL: no `set -x`, and -qq keeps apt's "Get:" lines out of the log.
RUN set -eu; \
    apt-get -qq update; \
    apt-get -qq install -y --no-install-recommends ca-certificates curl; \
    token="$(cat /tmp/edb-subscription-token)"; \
    curl -1sSLf "https://downloads.enterprisedb.com/${token}/standard/setup.deb.sh" | bash >/dev/null; \
    apt-get -qq install -y --no-install-recommends "postgresql${PG_MAJOR}-edb-wait-states=${EXT_VERSION}"

FROM scratch
ARG PG_MAJOR=18

COPY --from=builder /usr/share/doc/postgresql${PG_MAJOR}-edb-wait-states/copyright /licenses/edb-wait-states/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/edb_wait_states.so /lib/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/edb_wait_states.index.bc /lib/bitcode/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/edb_wait_states/ /lib/bitcode/edb_wait_states/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/edb_wait_states* /share/extension/

USER 65532:65532

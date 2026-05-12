ARG VALHALLA_BUILDER_IMAGE=valhalla/valhalla:run-latest

FROM ${VALHALLA_BUILDER_IMAGE} AS builder
LABEL org.opencontainers.image.authors="nilsnolde+github@proton.me"

RUN cd /usr/local/bin && \
  preserve="valhalla_service valhalla_build_tiles valhalla_build_config valhalla_build_admins valhalla_build_timezones valhalla_build_elevation valhalla_ways_to_edges valhalla_build_extract valhalla_export_edges valhalla_add_predicted_traffic valhalla_ingest_transit valhalla_convert_transit" && \
  mv $preserve .. && \
  for f in valhalla*; do rm -f $f; done && \
  cd .. && mv $preserve ./bin

FROM ubuntu:22.04 AS runner_base
LABEL org.opencontainers.image.authors="nilsnolde+github@proton.me"

RUN apt-get update > /dev/null && \
  export DEBIAN_FRONTEND=noninteractive && \
  apt-get install -y --no-install-recommends \
  libluajit-5.1-2 \
  libgdal30 \
  libzmq5 libczmq4 spatialite-bin libprotobuf-lite23 sudo locales \
  libsqlite3-0 libsqlite3-mod-spatialite libcurl4 \
  python3 python3-requests python3-shapely python-is-python3 \
  curl unzip moreutils jq ca-certificates > /dev/null && \
  rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local /usr/local

ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
ENV use_tiles_ignore_pbf=True
ENV build_tar=True
ENV serve_tiles=True
ENV update_existing_config=True
ENV default_speeds_config_url="https://raw.githubusercontent.com/OpenStreetMapSpeeds/schema/master/default_speeds.json"

ARG VALHALLA_UID=59999
ARG VALHALLA_GID=59999

RUN groupadd -g ${VALHALLA_GID} valhalla && \
  useradd -lmu ${VALHALLA_UID} -g valhalla valhalla && \
  mkdir -p /custom_files && \
  chown -R valhalla:valhalla /custom_files && \
  if [ ${VALHALLA_UID} != 59999 ] || [ ${VALHALLA_GID} != 59999 ]; then \
    chmod 0775 /custom_files; \
  else \
    usermod -aG sudo valhalla && echo "ALL ALL = (ALL) NOPASSWD: ALL" >> /etc/sudoers; \
  fi

COPY valhalla/scripts/ /valhalla/scripts/

# Dados estáticos embutidos na imagem.
# Requer que a pasta valhalla_data exista na raiz do contexto de build.
COPY --chown=valhalla:valhalla valhalla_data/ /custom_files/

RUN chmod +x /valhalla/scripts/*.sh && \
    find /custom_files -type d -exec chmod 775 {} \; && \
    find /custom_files -type f -exec chmod 664 {} \;

USER valhalla
WORKDIR /custom_files

RUN valhalla_build_config | jq type \
  && cat /usr/local/src/valhalla_version \
  && valhalla_build_tiles -v \
  && ls -la /usr/local/bin/valhalla*

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/lib:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:/lib32:/usr/lib32

EXPOSE 8002
ENTRYPOINT ["bash", "/valhalla/scripts/run.sh"]
CMD ["build_tiles"]

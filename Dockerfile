# Usando a imagem do Docker Hub como base para os binários
ARG VALHALLA_BUILDER_IMAGE=valhalla/valhalla:run-latest

# --- Estágio 1: Extrair binários ---
FROM $VALHALLA_BUILDER_IMAGE as builder
LABEL org.opencontainers.image.authors="nilsnolde+github@proton.me"

# Prepara os binários (removendo os problemáticos de landmarks)
RUN cd /usr/local/bin && \
  preserve="valhalla_service valhalla_build_tiles valhalla_build_config valhalla_build_admins valhalla_build_timezones valhalla_build_elevation valhalla_ways_to_edges valhalla_build_extract valhalla_export_edges valhalla_add_predicted_traffic valhalla_ingest_transit valhalla_convert_transit" && \
  mv $preserve .. && \
  for f in valhalla*; do rm $f; done && \
  cd .. && mv $preserve ./bin

# --- Estágio 2: Runner (AQUI MUDAMOS PARA UBUNTU 22.04) ---
# 22.04 (Jammy) porque é compatível com libprotobuf-lite.so.23
FROM ubuntu:22.04 as runner_base
LABEL org.opencontainers.image.authors="nilsnolde+github@proton.me"

# Instalação de dependências ajustadas para Ubuntu 22.04
RUN apt-get update > /dev/null && \
  export DEBIAN_FRONTEND=noninteractive && \
  apt-get install -y \
  libluajit-5.1-2 \
  libgdal30 \
  libzmq5 libczmq4 spatialite-bin libprotobuf-lite23 sudo locales \
  libsqlite3-0 libsqlite3-mod-spatialite libcurl4 \
  python3 python3-requests python3-shapely python-is-python3 \
  curl unzip moreutils jq spatialite-bin > /dev/null

# Copia os binários do Valhalla da imagem builder
COPY --from=builder /usr/local /usr/local

ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"
# Variáveis de ambiente padrão do Gisops
ENV use_tiles_ignore_pbf=True
ENV build_tar=True
ENV serve_tiles=True
ENV update_existing_config=True
ENV default_speeds_config_url="https://raw.githubusercontent.com/OpenStreetMapSpeeds/schema/master/default_speeds.json"

# Configuração de usuário
ARG VALHALLA_UID=59999
ARG VALHALLA_GID=59999

RUN groupadd -g ${VALHALLA_GID} valhalla && \
  useradd -lmu ${VALHALLA_UID} -g valhalla valhalla && \
  mkdir /custom_files && \
  if [ $VALHALLA_UID != 59999 ] || [ $VALHALLA_GID != 59999 ]; then chmod 0775 custom_files && chown valhalla:valhalla /custom_files; else usermod -aG sudo valhalla && echo "ALL             ALL = (ALL) NOPASSWD: ALL" >> /etc/sudoers; fi

COPY scripts/ /valhalla/scripts/

USER valhalla
WORKDIR /custom_files

# Smoke tests para garantir que o Valhalla roda
RUN valhalla_build_config | jq type \
  && cat /usr/local/src/valhalla_version \
  && valhalla_build_tiles -v \
  && ls -la /usr/local/bin/valhalla*

ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
ENV LD_LIBRARY_PATH /usr/local/lib:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:/lib32:/usr/lib32

EXPOSE 8002
ENTRYPOINT ["bash", "/valhalla/scripts/run.sh"]
CMD ["build_tiles"]
FROM nimlang/nim:2.2.4-alpine@sha256:47a9afd5e2d02f6a48fa13235462cb7356c4a04f7705689829f15b29d3fd8c4b AS compiler
WORKDIR /source
COPY config.nims nimby.lock ./
COPY src ./src
COPY tools/config.nims tools/runtimeRoot.nim ./tools/
COPY build/dependencies ./dependencies
ENV SCREEPS_PW_DEPS=/source/dependencies
RUN nim c -d:gameImage --out:/server src/server.nim
RUN nim c -d:gameImage --out:/runtime-root tools/runtimeRoot.nim

FROM screeps-pw-engine:7ff9722 AS runtime
USER root
COPY --from=compiler /runtime-root /runtime-root
RUN ["/runtime-root"]

FROM scratch
COPY --from=runtime /runtime /
COPY --from=compiler /server /app/server
COPY build/runtime /app/runtime
COPY build/release.json /app/release.json
ENV NODE_PATH=/opt:/opt/screeps/node_modules PATH=/usr/bin
WORKDIR /world
EXPOSE 8080
HEALTHCHECK NONE
ENTRYPOINT ["/app/server"]

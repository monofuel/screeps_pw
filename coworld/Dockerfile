ARG ENGINE_IMAGE=public.ecr.aws/q5f4m8t9/cogames@sha256:a99178510203da99bf58b48d545c3b3e025a33aeb78f51f0262d543516a9c5d6
FROM nimlang/nim:2.2.4-alpine@sha256:47a9afd5e2d02f6a48fa13235462cb7356c4a04f7705689829f15b29d3fd8c4b AS compiler
WORKDIR /source
COPY config.nims nimby.lock ./
COPY src ./src
COPY build/dependencies ./dependencies
ENV SCREEPS_PW_DEPS=/source/dependencies
RUN nim c -d:gameImage --out:/server src/server.nim
FROM ${ENGINE_IMAGE}
COPY --from=compiler /server /app/server
COPY build/runtime /app/runtime
COPY build/release.json /app/release.json
ENV NODE_PATH=/opt:/opt/screeps/node_modules PATH=/usr/bin
WORKDIR /world
EXPOSE 8080
HEALTHCHECK NONE
ENTRYPOINT ["/app/server"]

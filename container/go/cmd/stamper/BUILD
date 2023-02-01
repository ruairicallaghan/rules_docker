load("@bazel_gazelle//:def.bzl", "gazelle")
load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library")

# gazelle:prefix github.com/bazelbuild/rules_docker
gazelle(name = "gazelle")

go_library(
    name = "go_stamper",
    srcs = ["stamper.go"],
    importpath = "github.com/bazelbuild/rules_docker",
    visibility = ["//visibility:private"],
    deps = [
        "//container/go/pkg/compat:go_default_library",
        "//container/go/pkg/utils:go_default_library",
    ],
)

go_binary(
    name = "stamper",
    embed = [":go_stamper"],
    visibility = ["//visibility:public"],
)

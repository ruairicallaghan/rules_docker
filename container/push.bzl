# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""An implementation of container_push based on google/go-containerregistry.
This wraps the rules_docker.container.go.cmd.pusher.pusher executable in a
Bazel rule for publishing images.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@io_bazel_rules_docker//container:providers.bzl", "PushInfo", "STAMP_ATTR", "StampSettingInfo")
load(
    "//container:layer_tools.bzl",
    _gen_img_args = "generate_args_for_image",
    _get_layers = "get_from_target",
    _layer_tools = "tools",
)
load(
    "//skylib:path.bzl",
    "runfile",
)

def _get_runfile_path(ctx, f):
    if ctx.attr.windows_paths:
        return "%RUNFILES%\\{}".format(runfile(ctx, f).replace("/", "\\"))
    else:
        return "${RUNFILES}/%s" % runfile(ctx, f)

def _impl(ctx):
    """Core implementation of container_push."""

    # TODO: Possible optimization for efficiently pushing intermediate format after container_image is refactored, similar with the old python implementation, e.g., push-by-layer.

    pusher_args = []
    pusher_input = []

    stamper_args = []
    stamper_input = []

    digester_args = []
    digester_input = []

    # Parse and get destination registry to be pushed to
    registry = ctx.expand_make_variables("registry", ctx.attr.registry, {})
    repository = ctx.expand_make_variables("repository", ctx.attr.repository, {})

    # If a repository file is provided, override <repository> with tag value
    if ctx.file.repository_file:
        repository = "$(cat {})".format(_get_runfile_path(ctx, ctx.file.repository_file))
        pusher_input.append(ctx.file.repository_file)

    tag = ctx.expand_make_variables("tag", ctx.attr.tag, {})

    # If a tag file is provided, override <tag> with tag value
    if ctx.file.tag_file:
        tag = "$(cat {})".format(_get_runfile_path(ctx, ctx.file.tag_file))
        pusher_input.append(ctx.file.tag_file)

    stamp = ctx.attr.stamp[StampSettingInfo].value
    stamp_inputs = [ctx.info_file, ctx.version_file] if stamp else []
    for f in stamp_inputs:
        pusher_args += ["-stamp-info-file", "%s" % _get_runfile_path(ctx, f)]
        # stamper_args += ["-stamp-info-file", "%s" % f.path]
        stamper_args += ["-stamp-info-file", "%s" % ctx.info_file.path]
    pusher_input += stamp_inputs

    # Construct container_parts for input to pusher.
    image = _get_layers(ctx, ctx.label.name, ctx.attr.image)
    pusher_img_args, pusher_img_inputs = _gen_img_args(ctx, image, _get_runfile_path)
    pusher_args += pusher_img_args
    pusher_input += pusher_img_inputs
    digester_img_args, digester_img_inputs = _gen_img_args(ctx, image)
    digester_input += digester_img_inputs
    digester_args += digester_img_args
    tarball = image.get("legacy")
    if tarball:
        print("Pushing an image based on a tarball can be very " +
              "expensive. If the image set on %s is the output of a " % ctx.label +
              "docker_build, consider dropping the '.tar' extension. " +
              "If the image is checked in, consider using " +
              "container_import instead.")

    pusher_args.append("--format={}".format(ctx.attr.format))
    pusher_args.append("--dst={registry}/{repository}:{tag}".format(
        registry = registry,
        repository = repository,
        tag = tag,
    ))

    if ctx.attr.skip_unchanged_digest:
        pusher_args.append("-skip-unchanged-digest")
    if ctx.attr.insecure_repository:
        pusher_args.append("-insecure-repository")
    digester_args += ["--dst", str(ctx.outputs.digest.path), "--format", str(ctx.attr.format)]

    ctx.actions.run(
        inputs = digester_input,
        outputs = [ctx.outputs.digest],
        executable = ctx.executable._digester,
        arguments = digester_args,
        tools = ctx.attr._digester[DefaultInfo].default_runfiles.files,
        mnemonic = "ContainerPushDigest",
    )

    # If the docker toolchain is configured to use a custom client config
    # directory, use that instead
    toolchain_info = ctx.toolchains["@io_bazel_rules_docker//toolchains/docker:toolchain_type"].info
    if toolchain_info.client_config != "":
        pusher_args += ["-client-config-dir", str(toolchain_info.client_config)]

    pusher_runfiles = [ctx.executable._pusher] + pusher_input
    runfiles = ctx.runfiles(files = pusher_runfiles)
    runfiles = runfiles.merge(ctx.attr._pusher[DefaultInfo].default_runfiles)

    exe = ctx.actions.declare_file(ctx.label.name + ctx.attr.extension)
    ctx.actions.expand_template(
        template = ctx.file.tag_tpl,
        output = exe,
        substitutions = {
            "%{args}": " ".join(pusher_args),
            "%{container_pusher}": _get_runfile_path(ctx, ctx.executable._pusher),
        },
        is_executable = True,
    )

    stampd = ctx.actions.declare_file(ctx.label.name + ".stamp")
    stamper_args += ["--dest", str(ctx.outputs.stamp.path)]

    stamper_input += [ctx.info_file]
    ctx.actions.run(
        inputs = stamper_input,
        outputs = [ctx.outputs.stamp],
        executable = ctx.executable._stamper,
        arguments = stamper_args,
        tools = ctx.attr._stamper[DefaultInfo].default_runfiles.files,
    )

    return [
        DefaultInfo(
            executable = exe,
            runfiles = runfiles,
        ),
        OutputGroupInfo(
            exe = [exe],
        ),
        PushInfo(
            registry = registry,
            repository = repository,
            digest = ctx.outputs.digest,
            sha = ctx.outputs.stamp,
        ),
    ]

container_push_ = rule(
    attrs = dicts.add({
        "extension": attr.string(
            doc = "The file extension for the push script.",
        ),
        "format": attr.string(
            mandatory = True,
            values = [
                "OCI",
                "Docker",
            ],
            doc = "The form to push: Docker or OCI, default to 'Docker'.",
        ),
        "image": attr.label(
            allow_single_file = [".tar"],
            mandatory = True,
            doc = "The label of the image to push.",
        ),
        "insecure_repository": attr.bool(
            default = False,
            doc = "Whether the repository is insecure or not (http vs https)",
        ),
        "registry": attr.string(
            mandatory = True,
            doc = "The registry to which we are pushing.",
        ),
        "repository": attr.string(
            mandatory = True,
            doc = "The name of the image.",
        ),
        "repository_file": attr.label(
            allow_single_file = True,
            doc = "The label of the file with repository value. Overrides 'repository'.",
        ),
        "skip_unchanged_digest": attr.bool(
            default = False,
            doc = "Check if the container registry already contain the image's digest. If yes, skip the push for that image. " +
                  "Default to False. " +
                  "Note that there is no transactional guarantee between checking for digest existence and pushing the digest. " +
                  "This means that you should try to avoid running the same container_push targets in parallel.",
        ),
        "stamp": STAMP_ATTR,
        "stamp_tpl": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The script template to use.",
        ),
        "tag": attr.string(
            default = "latest",
            doc = "The tag of the image.",
        ),
        "tag_file": attr.label(
            allow_single_file = True,
            doc = "The label of the file with tag value. Overrides 'tag'.",
        ),
        "tag_tpl": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The script template to use.",
        ),
        "windows_paths": attr.bool(
            mandatory = True,
        ),
        "_digester": attr.label(
            default = "//container/go/cmd/digester",
            cfg = "exec",
            executable = True,
        ),
        "_pusher": attr.label(
            default = "//container/go/cmd/pusher",
            cfg = "target",
            executable = True,
            allow_files = True,
        ),
        "_stamper": attr.label(
            default = "//container/go/cmd/stamper",
            cfg = "target",
            executable = True,
        ),
    }, _layer_tools),
    executable = True,
    toolchains = ["@io_bazel_rules_docker//toolchains/docker:toolchain_type"],
    implementation = _impl,
    outputs = {
        "digest": "%{name}.digest",
        "stamp": "%{name}.stamp",
    },
)

# Pushes a container image to a registry.
def container_push(name, format, image, registry, repository, **kwargs):
    container_push_(
        name = name,
        format = format,
        image = image,
        registry = registry,
        repository = repository,
        extension = kwargs.pop("extension", select({
            "@bazel_tools//src/conditions:host_windows": ".bat",
            "//conditions:default": "",
        })),
        stamp_tpl = select({
            "@bazel_tools//src/conditions:host_windows": Label("//container:push-tag.bat.tpl"),
            "//conditions:default": Label("//container:stamp-tag.sh.tpl"),
        }),
        tag_tpl = select({
            "@bazel_tools//src/conditions:host_windows": Label("//container:push-tag.bat.tpl"),
            "//conditions:default": Label("//container:push-tag.sh.tpl"),
        }),
        windows_paths = select({
            "@bazel_tools//src/conditions:host_windows": True,
            "//conditions:default": False,
        }),
        **kwargs
    )

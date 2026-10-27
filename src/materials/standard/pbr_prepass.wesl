import bevy_pbr::{
    prepass::io::{VertexOutput as PbrVertexOutput, FragmentOutput},
    render::{
        pbr_prepass_functions,
        pbr_bindings,
        pbr_types,
        pbr_functions,
        pbr_functions::SampleBias,
        mesh_view_bindings::view,
    },
};

import bevy_pointcloud::{
    assets::shaders::pointcloud_bindings::pointcloud,
    render::prepass::prepass_io::VertexOutput,
};

fn discard_splat(vertex_output: VertexOutput) {
    @if(SHAPE_UVS_A && SPLAT_RADIUS) {
        let dist = distance(vertex_output.shape_uv, vec2<f32>(0.5, 0.5));
        if dist > pointcloud.radius {
            discard;
        }
    }
}

fn prepare_vertex_output(vertex_output: VertexOutput) -> PbrVertexOutput {
    var output: PbrVertexOutput;
    output.position = vertex_output.position;
    output.world_position = vertex_output.world_position;
    @if(NORMAL_PREPASS_OR_DEFERRED_PREPASS)
    output.world_normal = vertex_output.world_normal;

    @if(VERTEX_UVS_A)
    output.uv = vertex_output.uv;
    @if(VERTEX_UVS_B)
    output.uv_b = vertex_output.uv_b;
    @if(VERTEX_TANGENTS)
    output.world_tangent = vertex_output.world_tangent;
    @if(VERTEX_COLORS)
    output.color = vertex_output.color;
    @if(MOTION_VECTOR_PREPASS)
    output.previous_world_position = vertex_output.previous_world_position;
    @if(UNCLIPPED_DEPTH_ORTHO_EMULATION)
    output.unclipped_depth = vertex_output.unclipped_depth;
    @if(VERTEX_OUTPUT_INSTANCE_INDEX)
    output.instance_index = vertex_output.instance_index;
    @if(VISIBILITY_RANGE_DITHER)
    output.visibility_range_dither = vertex_output.visibility_range_dither;

    return output;
}

@if(PREPASS_FRAGMENT)
@fragment
fn fragment(
    vertex_output: VertexOutput,
    @builtin(front_facing) is_front: bool,
) -> FragmentOutput {
    discard_splat(vertex_output);

    let input = prepare_vertex_output(vertex_output);
    let flags = pbr_bindings::material.flags;
    let uv_transform = pbr_bindings::material.uv_transform;

    @if(VISIBILITY_RANGE_DITHER)
    pbr_functions::visibility_range_dither(input.position, input.visibility_range_dither);

    pbr_prepass_functions::prepass_sample_color_and_alpha_discard(input);

    var output: FragmentOutput;

    @if(UNCLIPPED_DEPTH_ORTHO_EMULATION)
    output.frag_depth = input.unclipped_depth;

    @if(NORMAL_PREPASS)
    if (flags & pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u {
        let double_sided =
            (flags & pbr_types::STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT) != 0u;
        let world_normal = pbr_functions::prepare_world_normal(
            input.world_normal,
            double_sided,
            is_front,
        );

        var normal = world_normal;

        @if(VERTEX_UVS) {
            @if(VERTEX_TANGENTS) {
                @if(STANDARD_MATERIAL_NORMAL_MAP) {
                    @if(STANDARD_MATERIAL_NORMAL_MAP_UV_B)
                    let uv = (uv_transform * vec3(input.uv_b, 1.0)).xy;
                    @else
                    let uv = (uv_transform * vec3(input.uv, 1.0)).xy;

                    var bias: SampleBias;
                    @if(MESHLET_MESH_MATERIAL_PASS) {
                        let mip_scale = exp2(view.mip_bias);
                        bias.ddx_uv = input.ddx_uv * mip_scale;
                        bias.ddy_uv = input.ddy_uv * mip_scale;
                    }
                    @else {
                        bias.mip_bias = view.mip_bias;
                    }

                    @if(MESHLET_MESH_MATERIAL_PASS)
                    let sampled_normal = textureSampleGrad(
                        pbr_bindings::normal_map_texture,
                        pbr_bindings::normal_map_sampler,
                        uv,
                        bias.ddx_uv,
                        bias.ddy_uv,
                    ).rgb;
                    @else
                    let sampled_normal = textureSampleBias(
                        pbr_bindings::normal_map_texture,
                        pbr_bindings::normal_map_sampler,
                        uv,
                        bias.mip_bias,
                    ).rgb;

                    let tbn =
                        pbr_functions::calculate_tbn_mikktspace(normal, input.world_tangent);
                    normal = pbr_functions::apply_normal_mapping(
                        flags,
                        tbn,
                        double_sided,
                        is_front,
                        sampled_normal,
                    );
                }
            }
        }

        output.normal = vec4(normal * 0.5 + vec3(0.5), 1.0);
    } else {
        output.normal = vec4(input.world_normal * 0.5 + vec3(0.5), 1.0);
    }

    @if(MOTION_VECTOR_PREPASS && MESHLET_MESH_MATERIAL_PASS)
    output.motion_vector = input.motion_vector;
    @if(MOTION_VECTOR_PREPASS && !MESHLET_MESH_MATERIAL_PASS)
    output.motion_vector = pbr_prepass_functions::calculate_motion_vector(
        input.world_position,
        input.previous_world_position,
    );

    return output;
}
@else
@fragment
fn fragment(
    vertex_output: VertexOutput,
    @builtin(front_facing) _is_front: bool,
) {
    discard_splat(vertex_output);
    pbr_prepass_functions::prepass_sample_color_and_alpha_discard(
        prepare_vertex_output(vertex_output),
    );
}

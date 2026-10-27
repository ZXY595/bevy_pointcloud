import bevy_pbr::render::{
    pbr_types,
    pbr_functions::alpha_discard,
    pbr_fragment::pbr_input_from_standard_material,
};
import bevy_pbr::decal::clustered::apply_decals;
// ============================================================================
// BEGIN CUSTOM PATCH: [PointCloudPlugin] - Point size and depth attenuation
// `VertexOutput` is no more imported in each case because imported below.
// ============================================================================

@if(PREPASS_PIPELINE)
import bevy_pbr::{
    deferred::functions::deferred_output,
    prepass::io::{VertexOutput as PbrVertexOutput, FragmentOutput},
};
@else
import bevy_pbr::render::{
    forward_io::{VertexOutput as PbrVertexOutput, FragmentOutput},
    pbr_functions::{apply_pbr_lighting, main_pass_post_lighting_processing},
    pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
};

@if(PREPASS_PIPELINE)
import bevy_pointcloud::render::prepass::prepass_io::VertexOutput;
@else
import bevy_pointcloud::assets::shaders::forward_io::VertexOutput;

import bevy_pointcloud::assets::shaders::{
    functions,
    pointcloud_bindings::pointcloud,
};
// ============================================================================
// END CUSTOM PATCH: [PointCloudPlugin]
// ============================================================================

@if(VISIBILITY_RANGE_DITHER)
import bevy_pbr::render::pbr_functions::visibility_range_dither;

@if(MESHLET_MESH_MATERIAL_PASS)
import bevy_pbr::meshlet::visibility_buffer_resolve::resolve_vertex_output;

@if(OIT_ENABLED)
import bevy_core_pipeline::oit::draw::oit_draw;

@if(FORWARD_DECAL)
import bevy_pbr::decal::forward::get_forward_decal_info;

@fragment
fn fragment(
@if(MESHLET_MESH_MATERIAL_PASS)
    @builtin(position) frag_coord: vec4<f32>,
@else
    vertex_output: VertexOutput,
    @builtin(front_facing) is_front: bool,
) -> FragmentOutput {
@if(MESHLET_MESH_MATERIAL_PASS)
    let vertex_output = resolve_vertex_output(frag_coord);
@if(MESHLET_MESH_MATERIAL_PASS)
    let is_front = true;


// ============================================================================
// BEGIN CUSTOM PATCH: [PointCloudPlugin] - Point size and depth attenuation
// ============================================================================

@if(SHAPE_UVS_A) {    @if(SPLAT_RADIUS) {        // Perfect circle
        let dist = distance(vertex_output.shape_uv, vec2<f32>(0.5, 0.5));

        if dist > pointcloud.radius {
            discard;
        }
    }
}

    var in: PbrVertexOutput;

    in.position                    = vertex_output.position;
    in.world_position              = vertex_output.world_position;
    in.world_normal                = vertex_output.world_normal;

    @if(VERTEX_UVS_A)
    in.uv = vertex_output.uv;
    @if(VERTEX_UVS_B)
    in.uv_b = vertex_output.uv_b;
    @if(VERTEX_TANGENTS)
    in.world_tangent = vertex_output.world_tangent;
    @if(VERTEX_COLORS)
    in.color = vec4<f32>(
            functions::srgb_to_rgb_simple(vertex_output.color.xyz),
            vertex_output.color.a,
    );
    @if(VERTEX_OUTPUT_INSTANCE_INDEX)
    in.instance_index = vertex_output.instance_index;
    @if(VISIBILITY_RANGE_DITHER)
    in.visibility_range_dither = vertex_output.visibility_range_dither;

// ============================================================================
// END CUSTOM PATCH: [PointCloudPlugin]
// ============================================================================

    // If we're in the crossfade section of a visibility range, conditionally
    // discard the fragment according to the visibility pattern.
@if(VISIBILITY_RANGE_DITHER)
    visibility_range_dither(in.position, in.visibility_range_dither);

@if(FORWARD_DECAL)
    let forward_decal_info = get_forward_decal_info(in);
@if(FORWARD_DECAL)
    in.world_position = forward_decal_info.world_position;
@if(FORWARD_DECAL)
    in.uv = forward_decal_info.uv;

    // generate a PbrInput struct from the StandardMaterial bindings
    var pbr_input = pbr_input_from_standard_material(in, is_front);

    // alpha discard
    pbr_input.material.base_color = alpha_discard(
        pbr_input.material.flags,
        pbr_input.material.alpha_cutoff,
        pbr_input.material.base_color,
    );

    // clustered decals
    apply_decals(&pbr_input);

@if(PREPASS_PIPELINE)
    let out = deferred_output(in, pbr_input);
@if(!PREPASS_PIPELINE)
    var out: FragmentOutput;
@if(!PREPASS_PIPELINE)
    if (pbr_input.material.flags & STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u {
        out.color = apply_pbr_lighting(pbr_input);
    } else {
        out.color = pbr_input.material.base_color;
    }

@if(!PREPASS_PIPELINE)
    out.color = main_pass_post_lighting_processing(pbr_input, out.color);

@if(OIT_ENABLED) {    let alpha_mode = pbr_input.material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_ALPHA_MODE_RESERVED_BITS;
    if alpha_mode != pbr_types::STANDARD_MATERIAL_FLAGS_ALPHA_MODE_OPAQUE {
        // The fragments will only be drawn during the oit resolve pass.
        oit_draw(in.position, out.color);
        discard;
    }
}

@if(FORWARD_DECAL)
    out.color.a = min(forward_decal_info.alpha, out.color.a);

    return out;
}

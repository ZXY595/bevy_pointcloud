import bevy_pbr::{
    prepass::bindings as prepass_bindings,
    render::{
        skinning,
        morph,
        mesh_view_bindings::view,
        view_transformations::position_world_to_view,
    },
};
@if(PREPASS_FRAGMENT)
import bevy_pbr::prepass::io::FragmentOutput;


import bevy_pointcloud::{
    assets::shaders::{
        functions,
        pointcloud_bindings::pointcloud,
        pointcloud_functions,
    },
    render::prepass::prepass_io::{ShapeInput, InstanceInput, VertexOutput},
};
@if(DEFERRED_PREPASS)
import bevy_pbr::render::rgb9e5;

fn discard_splat(input: VertexOutput) {
    @if(SHAPE_UVS_A && SPLAT_RADIUS) {
        let dist = distance(input.shape_uv, vec2<f32>(0.5, 0.5));
        if dist > pointcloud.radius {
            discard;
        }
    }
}

@vertex
fn vertex(
    shape: ShapeInput,
    vertex: InstanceInput,
) -> VertexOutput {
    var out: VertexOutput;

    out.instance_index = 0;

    // We assume VERTEX_POSITIONS & SHAPE_POSITIONS are set.

    let world_from_local = pointcloud_functions::get_world_from_local();

    let point_world_position =
        pointcloud_functions::mesh_position_local_to_world(
            world_from_local,
            vec4<f32>(vertex.position, 1.0)
        ).xyz;

    let point_view_position = position_world_to_view(point_world_position);

    let radius = pointcloud_functions::compute_point_radius(
        vertex.position,
        world_from_local,
        point_view_position
    );

    @if(NORMAL_PREPASS_OR_DEFERRED_PREPASS && SHAPE_NORMALS)
    let shape_normal = shape.normal;
    @if(NORMAL_PREPASS_OR_DEFERRED_PREPASS && !SHAPE_NORMALS)
    let shape_normal = pointcloud.default_normal.xyz;

    // Get point normal (fallback to default)
    @if(INSTANCE_NORMALS)
    let normal = vertex.normal;
    @else
    let normal = pointcloud.default_normal.xyz;

    // Prepare tangent
    @if(VERTEX_TANGENTS)
    let tangent = vertex.tangent.xyz;
    @else
    let tangent = vec3<f32>(0.0);

    // Compute vertex positions
    @if(NORMAL_PREPASS_OR_DEFERRED_PREPASS)
    let pos = pointcloud_functions::compute_point_vertex_positions_normal(
            point_world_position,
            world_from_local,
            shape.position,
            shape_normal,
            radius,
            normal,
            tangent,
    );
    @else
    let pos = pointcloud_functions::compute_point_vertex_positions(
            point_world_position,
            world_from_local,
            shape.position,
            radius,
            normal,
            tangent,
    );

    out.position = pos.clip_position;
    out.world_position = vec4<f32>(pos.world_position, 1.0);

@if(UNCLIPPED_DEPTH_ORTHO_EMULATION) {
    out.unclipped_depth = out.position.z;
    out.position.z = min(out.position.z, 1.0); // Clamp depth to avoid clipping
}

@if(INSTANCE_UVS_A)
out.uv = vertex.uv;

@if(INSTANCE_UVS_B)
out.uv_b = vertex.uv_b;

@if(NORMAL_PREPASS_OR_DEFERRED_PREPASS && VERTEX_NORMALS)
out.world_normal = pos.world_normal;

@if(NORMAL_PREPASS_OR_DEFERRED_PREPASS && VERTEX_TANGENTS)
out.world_tangent = pointcloud_functions::mesh_tangent_local_to_world(
        world_from_local,
        vertex.tangent,
);

@if(VERTEX_COLORS)
out.color = vertex.color;


// Compute the motion vector for TAA among other purposes. For this we need
// to know where the vertex was last frame.
@if(MOTION_VECTOR_PREPASS) {
    let prev_vertex = vertex;


    // Use vertex_no_morph.instance_index instead of prev_vertex.instance_index to work around a wgpu dx12 bug.
    // See https://github.com/gfx-rs/naga/issues/2416
    let prev_model = pointcloud_functions::get_previous_world_from_local();

    let prev_point_world_position = pointcloud_functions::mesh_position_local_to_world(
        prev_model,
        vec4<f32>(vertex.position, 1.0)
    ).xyz;

    // Compute previous vertex positions
    @if(NORMAL_PREPASS_OR_DEFERRED_PREPASS) {        let prev_pos = pointcloud_functions::compute_point_vertex_positions_normal(
            prev_point_world_position,
            prev_model,
            shape.position,
            shape_normal,
            radius,
            normal,
            tangent,
        );
    }
    @else {
        let prev_pos = pointcloud_functions::compute_point_vertex_positions(
            prev_point_world_position,
            prev_model,
            shape.position,
            radius,
            normal,
            tangent,
        );
    }

    out.previous_world_position = vec4<f32>(prev_pos.world_position, 1.0);
}


@if(VISIBILITY_RANGE_DITHER) {    let mesh_world_from_local = pointcloud_functions::get_world_from_local();

    out.visibility_range_dither = pointcloud_functions::get_visibility_range_dither_level(mesh_world_from_local[3]);
}

@if(SHAPE_UVS_A) {    out.shape_uv = shape.uv;
}

    return out;
}


@if(PREPASS_FRAGMENT)
@fragment
fn fragment(input: VertexOutput) -> FragmentOutput {
    discard_splat(input);

    var output: FragmentOutput;

    @if(NORMAL_PREPASS)
    output.normal = vec4(input.world_normal * 0.5 + vec3(0.5), 1.0);

    @if(UNCLIPPED_DEPTH_ORTHO_EMULATION)
    output.frag_depth = input.unclipped_depth;

    @if(MOTION_VECTOR_PREPASS) {
        let clip_position_t = view.unjittered_clip_from_world * input.world_position;
        let clip_position = clip_position_t.xy / clip_position_t.w;
        let previous_clip_position_t =
            prepass_bindings::previous_view_uniforms.unjittered_clip_from_world *
            input.previous_world_position;
        let previous_clip_position =
            previous_clip_position_t.xy / previous_clip_position_t.w;
        output.motion_vector =
            (clip_position - previous_clip_position) * vec2(0.5, -0.5);
    }

    @if(DEFERRED_PREPASS) {
        output.deferred = vec4(
            0u,
            rgb9e5::vec3_to_rgb9e5_(vec3(1.0, 0.0, 1.0)),
            0u,
            0u,
        );
        output.deferred_lighting_pass_id = 1u;
    }

    return output;
}
@else
@fragment
fn fragment(input: VertexOutput) {
    discard_splat(input);
}

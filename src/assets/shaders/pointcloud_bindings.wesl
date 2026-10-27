
import bevy_pointcloud::assets::shaders::pointcloud_types::PointCloud;
@group(2) @binding(1) public var<uniform> pointcloud: PointCloud;

@group(2) @binding(2) public var visible_nodes: texture_2d<u32>;

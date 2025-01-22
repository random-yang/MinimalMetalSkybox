//
//  shader.metal
//  Metal_skybox
//
//  Created by randomyang on 2025/1/22.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 texCoord;
};

vertex VertexOut skyboxVertex(
    VertexIn in [[stage_in]],
    constant float4x4 &viewProjectionMatrix [[buffer(1)]]
) {
    VertexOut out;
    out.position = viewProjectionMatrix * float4(in.position, 1.0);
    out.texCoord = in.position; // 使用顶点位置作为采样方向
    return out;
}

fragment float4 skyboxFragment(
    VertexOut in [[stage_in]],
    texturecube<float> cubeTexture [[texture(0)]]
) {
    constexpr sampler cubeSampler(filter::linear, mip_filter::linear);
    return cubeTexture.sample(cubeSampler, in.texCoord);
}


// 正方形的顶点着色器
vertex VertexOut squareVertex(const device float3* vertices [[buffer(0)]],
                            constant float4x4& viewProjectionMatrix [[buffer(1)]],
                            uint vertexID [[vertex_id]]) {
    VertexOut out;
    float3 position = vertices[vertexID];
    out.position = viewProjectionMatrix * float4(position, 1.0);
    return out;
}

// 正方形的片段着色器
fragment float4 squareFragment(constant float4* color [[buffer(0)]]) {
    return *color;
}
#include <metal_stdlib>
using namespace metal;

kernel void mlsdCopyImage(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    uint2 position [[thread_position_in_grid]])
{
    if (position.x < destination.get_width() && position.y < destination.get_height()) {
        destination.write(source.read(position), position);
    }
}

struct LineVertexOutput {
    float4 position [[position]];
    float2 presentationPixel;
    float2 startPixel;
    float2 endPixel;
    float halfWidth;
};

vertex LineVertexOutput mlsdLineVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device float4 *segments [[buffer(0)]],
    constant float4x4 &textureTransform [[buffer(1)]],
    constant float2 &presentationSize [[buffer(2)]],
    constant float &lineWidth [[buffer(3)]])
{
    const float4 segment = segments[instanceID];
    const float2 startPixel = float2(segment.x, 1.0 - segment.y) * presentationSize;
    const float2 endPixel = float2(segment.z, 1.0 - segment.w) * presentationSize;
    const float2 direction = endPixel - startPixel;
    const float segmentLength = max(length(direction), 0.0001);
    const float2 tangent = direction / segmentLength;
    const float2 normal = float2(-tangent.y, tangent.x);
    const float halfWidth = lineWidth * 0.5;
    const float extent = halfWidth + 1.0;
    const float2 corners[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    const float2 corner = corners[vertexID];
    const float2 presentationPixel = mix(startPixel, endPixel, (corner.x + 1.0) * 0.5)
        + tangent * corner.x * extent + normal * corner.y * extent;
    const float2 presentationUV = presentationPixel / presentationSize;
    const float4 storedUV = textureTransform * float4(presentationUV, 0.0, 1.0);

    LineVertexOutput output;
    output.position = float4(storedUV.x * 2.0 - 1.0, 1.0 - storedUV.y * 2.0, 0.0, 1.0);
    output.presentationPixel = presentationPixel;
    output.startPixel = startPixel;
    output.endPixel = endPixel;
    output.halfWidth = halfWidth;
    return output;
}

fragment float4 mlsdLineFragment(
    LineVertexOutput input [[stage_in]],
    constant float4 &lineColor [[buffer(0)]])
{
    const float2 segment = input.endPixel - input.startPixel;
    const float denominator = max(dot(segment, segment), 0.0001);
    const float position = clamp(dot(input.presentationPixel - input.startPixel, segment)
        / denominator, 0.0, 1.0);
    const float distance = length(input.presentationPixel
        - (input.startPixel + position * segment));
    const float coverage = 1.0 - smoothstep(input.halfWidth - 0.5,
                                            input.halfWidth + 0.5,
                                            distance);
    return float4(lineColor.rgb, lineColor.a * coverage);
}

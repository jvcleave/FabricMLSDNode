#include <metal_stdlib>

using namespace metal;

kernel void resizeTextureForMLSD(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant float4x4 &textureTransform [[buffer(0)]],
    constant uint2 &presentationExtent [[buffer(1)]],
    uint2 position [[thread_position_in_grid]])
{
    const uint width = destination.get_width();
    const uint height = destination.get_height();
    if (position.x >= width || position.y >= height) {
        return;
    }

    const float2 sourceSize(
        float(presentationExtent.x),
        float(presentationExtent.y)
    );
    const float2 destinationSize(width, height);
    const float2 sourceStart = float2(position) * sourceSize / destinationSize;
    const float2 sourceEnd = float2(position + 1) * sourceSize / destinationSize;
    const uint2 firstPixel = min(uint2(floor(sourceStart)), presentationExtent - 1);
    const uint2 endPixel = min(uint2(ceil(sourceEnd)), presentationExtent);
    const uint2 storedExtent(source.get_width(), source.get_height());

    float3 accumulated = 0.0f;
    float accumulatedWeight = 0.0f;
    for (uint sourceY = firstPixel.y; sourceY < endPixel.y; ++sourceY) {
        const float yWeight = max(
            0.0f,
            min(sourceEnd.y, float(sourceY + 1)) -
                max(sourceStart.y, float(sourceY))
        );
        for (uint sourceX = firstPixel.x; sourceX < endPixel.x; ++sourceX) {
            const float xWeight = max(
                0.0f,
                min(sourceEnd.x, float(sourceX + 1)) -
                    max(sourceStart.x, float(sourceX))
            );
            const float weight = xWeight * yWeight;
            const float2 presentationCoordinate =
                (float2(sourceX, sourceY) + 0.5f) / sourceSize;
            const float4 transformedCoordinate = textureTransform * float4(
                presentationCoordinate,
                0.0f,
                1.0f
            );
            const float2 storedCoordinate = clamp(
                transformedCoordinate.xy / transformedCoordinate.w,
                0.0f,
                1.0f
            );
            const uint2 storedPixel = min(
                uint2(storedCoordinate * float2(storedExtent)),
                storedExtent - 1
            );
            accumulated += source.read(storedPixel).rgb * weight;
            accumulatedWeight += weight;
        }
    }
    const float3 rgb = saturate(accumulated / max(accumulatedWeight, 1e-8f));
    destination.write(float4(rgb, 1.0f), position);
}

#include <metal_stdlib>

using namespace metal;

kernel void resizeTextureForMLSD(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    uint2 position [[thread_position_in_grid]])
{
    const uint width = destination.get_width();
    const uint height = destination.get_height();
    if (position.x >= width || position.y >= height) {
        return;
    }

    const float2 sourceSize(source.get_width(), source.get_height());
    const float2 destinationSize(width, height);
    const float2 sourceStart = float2(position) * sourceSize / destinationSize;
    const float2 sourceEnd = float2(position + 1) * sourceSize / destinationSize;
    const uint2 sourceExtent(source.get_width(), source.get_height());
    const uint2 firstPixel = min(uint2(floor(sourceStart)), sourceExtent - 1);
    const uint2 endPixel = min(uint2(ceil(sourceEnd)), sourceExtent);

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
            accumulated += source.read(uint2(sourceX, sourceY)).rgb * weight;
            accumulatedWeight += weight;
        }
    }
    const float3 rgb = saturate(accumulated / max(accumulatedWeight, 1e-8f));
    destination.write(float4(rgb, 1.0f), position);
}

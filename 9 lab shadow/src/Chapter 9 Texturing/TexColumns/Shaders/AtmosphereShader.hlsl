// MinimalAtmosphere.hlsl
Texture2D gDepthBuffer : register(t0);
SamplerState gsamPointClamp : register(s0);

struct VSOut
{
    float4 PosH : SV_POSITION;
    float2 TexC : TEXCOORD;
};

VSOut VS(uint vid : SV_VertexID)
{
    VSOut output;
    float2 positions[3] = { float2(-1, -1), float2(-1, 3), float2(3, -1) };
    output.PosH = float4(positions[vid], 1.0, 1.0); // z = 1.0
    output.TexC = output.PosH.xy * 0.5 + 0.5;
    return output;
}

float4 PS(VSOut pin) : SV_TARGET
{
    float depth = gDepthBuffer.Sample(gsamPointClamp, pin.TexC).r;
    if (depth < 1.0f - 1e-6f)
        discard;
    return float4(1, 0, 0, 1); // красный
}
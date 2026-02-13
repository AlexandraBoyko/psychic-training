struct VSOut
{
    float4 PosH : SV_POSITION;
    float2 TexC : TEXCOORD;
};

VSOut VS(uint vid : SV_VertexID)
{
    VSOut output;
    float2 positions[3] = { float2(-1, -1), float2(-1, 3), float2(3, -1) };
    output.PosH = float4(positions[vid], 0, 1);
    output.TexC = output.PosH.xy * 0.5 + 0.5;
    return output;
}

float4 PS(VSOut pin) : SV_TARGET
{
    return float4(1, 0, 0, 1);
}
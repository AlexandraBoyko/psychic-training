

Texture2D gDepthBuffer : register(t0);
SamplerState gsamPointClamp : register(s0);

cbuffer cbAtmosphere : register(b0)
{
    float3 gSunDirection; 
    float gSunStrength;
    float gRayleigh;
    float gMie; 
    float gTurbidity;
    float2 _pad0;

    float2 gInvRenderTargetSize;
    float2 _pad1;
    float4x4 gInvProj;
    float4x4 gInvView; 
};

static const float PI = 3.14159265359f;


float3 ReconstructSkyboxViewDirWS(int2 pix, float2 invScreenSize, float4x4 invProj, float4x4 invView)
{
    float2 uv = (float2(pix) + 0.5f) * invScreenSize;
    float2 ndc;
    ndc.x = uv.x * 2.0f - 1.0f;
    ndc.y = 1.0f - uv.y * 2.0f;

    float4 viewRay = mul(float4(ndc, 1.0f, 1.0f), invProj);
    viewRay.xyz /= max(viewRay.w, 1e-6f);
    float3 viewDirVS = normalize(viewRay.xyz);
    float3 viewDirWS = normalize(mul(float4(viewDirVS, 0.0f), invView).xyz);
    return viewDirWS;
}


void GetOpticalPathAndSunsetFactor(float3 sunDir, out float opticalPathNorm, out float sunsetFactor)
{
    float sunElevation = max(sunDir.y, 0.02f);
    float airMass = 1.0f / sunElevation;
    opticalPathNorm = saturate((airMass - 1.0f) / 15.0f);
    sunsetFactor = 1.0f - exp(-opticalPathNorm * 2.0f);
}

float RayleighPhase(float cosTheta)
{
    return 3.0f / (16.0f * PI) * (1.0f + cosTheta * cosTheta);
}

float MiePhase(float cosTheta, float g)
{
    float g2 = g * g;
    float denom = 1.0f + g2 - 2.0f * g * cosTheta;
    return (1.0f - g2) / (4.0f * PI * pow(max(denom, 1e-6f), 1.5f));
}

float3 ComputeAtmosphereSky(float3 viewDir, float3 sunDir)
{
    float opticalPathNorm, sunsetFactor;
    GetOpticalPathAndSunsetFactor(sunDir, opticalPathNorm, sunsetFactor);

    float sunCos = saturate(dot(viewDir, sunDir));
    float height = saturate(viewDir.y * 0.5f + 0.5f);
    float horizon = 1.0f - height;
    float horizonBand = saturate(1.0f - viewDir.y * 2.0f);

    float3 zenithColor = float3(0.25f, 0.5f, 0.95f);
    float3 horizonColorDay = float3(0.7f, 0.8f, 0.95f);
    float3 horizonColorSunset = float3(1.0f, 0.55f, 0.2f);
    float3 horizonColor = lerp(horizonColorDay, horizonColorSunset, sunsetFactor * horizonBand);
    float3 skyGradient = lerp(horizonColor, zenithColor, height);

    float phaseR = RayleighPhase(sunCos);
    float rayleighAmount = gRayleigh * (1.0f + 0.3f * horizon);
    float3 rayleighTint = float3(0.3f, 0.5f, 1.0f);
    float rayleighPathAtten = 1.0f - opticalPathNorm * 0.7f;
    float3 rayleighContribution = rayleighTint * phaseR * rayleighAmount * max(rayleighPathAtten, 0.2f);

    float phaseM = MiePhase(sunCos, -0.76f);
    float turbidityScale = 0.4f + 0.6f * gTurbidity;
    float mieAmount = gMie * turbidityScale * (0.6f + 0.4f * horizon) * (1.0f + 0.5f * opticalPathNorm);
    float3 mieHaze = float3(0.85f, 0.85f, 0.9f);
    float3 mieContribution = mieHaze * phaseM * mieAmount;
    float sunGlow = pow(sunCos, 4.0f) * gMie * gTurbidity * 2.0f;
    float3 mieSunHaloColor = lerp(float3(1.0f, 0.98f, 0.9f), float3(1.0f, 0.7f, 0.4f), sunsetFactor);
    float3 mieSunHalo = mieSunHaloColor * sunGlow;

    float3 sunsetGlow = float3(1.0f, 0.5f, 0.15f) * sunsetFactor * horizonBand * (0.3f + 0.4f * sunCos);
    skyGradient += sunsetGlow;

    float hazeBlend = saturate((gMie * 0.5f + (gTurbidity - 1.0f) * 0.3f));
    float3 hazeGray = float3(0.6f, 0.65f, 0.75f);
    float3 skyWithScatter = skyGradient + rayleighContribution + mieContribution + mieSunHalo;
    float3 skyColor = lerp(skyWithScatter, hazeGray, hazeBlend * 0.5f);

    float sunScale = 0.4f + 0.6f * saturate(gSunStrength / 5.0f);
    return saturate(skyColor * sunScale);
}

float3 ComputeSunDisc(float3 viewDir, float3 sunDir, float radius, float intensity)
{
    float cosAngle = dot(viewDir, sunDir);
    float disc = smoothstep(radius - 0.002f, radius, cosAngle);

    float opticalPathNorm, sunsetFactor;
    GetOpticalPathAndSunsetFactor(sunDir, opticalPathNorm, sunsetFactor);

    float3 sunColorDay = float3(1.0f, 1.0f, 1.0f);
    float3 sunColorSunset = float3(1.0f, 0.6f, 0.2f);
    float3 sunColor = lerp(sunColorDay, sunColorSunset, sunsetFactor);
    return sunColor * intensity * disc;
}

struct VSOut
{
    float4 PosH : SV_POSITION;
    float2 TexC : TEXCOORD;
};

VSOut VS(uint vid : SV_VertexID)
{
    VSOut output;
    float2 positions[3] =
    {
        float2(-1, -1),
        float2(-1, 3),
        float2(3, -1)
    };
    output.PosH = float4(positions[vid], 0, 1);
    output.TexC = output.PosH.xy * 0.5 + 0.5;
    return output;
}

float4 PS(VSOut pin) : SV_TARGET
{

    float depth = gDepthBuffer.Sample(gsamPointClamp, pin.TexC).r;

    if (depth < 1.0f - 1e-6f)
        discard;


    int2 pix = int2(pin.PosH.xy);
    float3 viewDir = ReconstructSkyboxViewDirWS(pix, gInvRenderTargetSize, gInvProj, gInvView);

    float3 sunDir = normalize(gSunDirection);


    float3 skyColor = ComputeAtmosphereSky(viewDir, sunDir);

    float3 sunDisc = ComputeSunDisc(viewDir, sunDir, 0.998f, min(gSunStrength * 0.8f, 3.0f));

    return float4(skyColor + sunDisc, 1.0f);
}
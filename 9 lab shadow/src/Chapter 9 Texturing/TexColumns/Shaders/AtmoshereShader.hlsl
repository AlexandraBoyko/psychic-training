

cbuffer PassConstants : register(b0)
{
    float4x4 View;
    float4x4 InvView;
    float4x4 Proj;
    float4x4 InvProj;
    float4x4 ViewProj;
    float4x4 InvViewProj;
    float3 EyePosW;
    float cbPerObjectPad1;
    float2 RenderTargetSize;
    float2 InvRenderTargetSize;
    float NearZ;
    float FarZ;
    float TotalTime;
    float DeltaTime;
};

cbuffer AtmosphereConstants : register(b1)
{
    float3 SunDirection; // направление К солнцу
    float SunIntensity;
    float3 RayleighScattering;
    float MieG;
    float3 MieScattering;
    float DensityMultiplier;
    float PollutionLevel;
    float SunAngularRadius;
    float padding[2];
};

struct VS_INPUT
{
    float3 PosL : POSITION;
    float3 NormalL : NORMAL;
    float2 TexC : TEXCOORD;
    float3 TangentL : TANGENT;
};

struct VS_OUTPUT
{
    float4 PosH : SV_POSITION;
    float3 WorldPos : TEXCOORD0;
    float3 ViewDir : TEXCOORD1;
};

VS_OUTPUT VS(VS_INPUT vin)
{
    VS_OUTPUT vout;

    float3 worldPos = vin.PosL + EyePosW;

    vout.WorldPos = worldPos;

    vout.ViewDir = normalize(worldPos - EyePosW);

    float4 posW = float4(worldPos, 1.0f);
    vout.PosH = mul(posW, ViewProj);

    return vout;
}

float getRayleighPhase(float cosTheta)
{
    return 0.75f * (1.0f + cosTheta * cosTheta);
}

float getMiePhase(float cosTheta, float g)
{
    float g2 = g * g;
    return 0.75f * ((1.0f - g2) / pow(1.0f + g2 - 2.0f * g * cosTheta, 1.5f));
}

float4 PS(VS_OUTPUT pin) : SV_TARGET
{
    float3 viewDir = normalize(pin.ViewDir);
    float3 sunDir = normalize(SunDirection); // уже направление К солнцу
    float cosTheta = dot(viewDir, sunDir);
    

    float3 up = float3(0, 1, 0);
    float viewElevation = dot(viewDir, up);
    float sunElevation = dot(sunDir, up);
    
    float3 horizonColor = float3(0.7f, 0.8f, 1.0f);
    float3 zenithColor = float3(0.15f, 0.25f, 0.5f);
    
   
    float densityFactor = saturate((DensityMultiplier - 0.1f) / 9.9f);
    densityFactor = pow(densityFactor, 0.6f);
    
    float3 horizonHighDensity = float3(0.9f, 0.6f, 0.4f);
    float3 zenithHighDensity = float3(0.4f, 0.3f, 0.25f);
    
    horizonColor = lerp(horizonColor, horizonHighDensity, densityFactor);
    zenithColor = lerp(zenithColor, zenithHighDensity, densityFactor);
    
    float elevationFactor = saturate((viewElevation + 1.0f) * 0.5f);
    elevationFactor = pow(elevationFactor, 0.7f);
    float3 baseSkyColor = lerp(horizonColor, zenithColor, elevationFactor);
    
    float pollutionFactor = 1.0f + PollutionLevel * 1.5f;
    float3 rayleigh = RayleighScattering * pollutionFactor;
    float3 mie = MieScattering * (1.0f + PollutionLevel * 3.0f);
    
    float rayleighPhase = getRayleighPhase(cosTheta);
    float3 rayleighContribution = rayleigh * rayleighPhase * SunIntensity * 2.0f;
    

    float3 rayleighShift = float3(1.0f, 1.0f, 1.0f);
    rayleighShift.r = 1.0f + densityFactor * 1.5f;
    rayleighShift.g = 1.0f + densityFactor * 0.5f;
    rayleighShift.b = 1.0f - densityFactor * 0.7f;
    rayleighContribution *= rayleighShift;
    

    float miePhase = getMiePhase(cosTheta, MieG);
    float3 mieContribution = mie * miePhase * SunIntensity * 1.0f;
    
    float3 mieShift = float3(1.0f, 0.9f, 0.7f);
    mieShift.r = 1.0f + densityFactor * 1.2f;
    mieShift.g = 1.0f - densityFactor * 0.3f;
    mieShift.b = 1.0f - densityFactor * 0.5f;
    mieContribution *= mieShift;
    

    float3 skyColor = baseSkyColor * 0.3f + rayleighContribution + mieContribution;
    

    float sunAngularRadius = SunAngularRadius;
    float sunCosAngle = cos(sunAngularRadius);
    float sunProximity = saturate((cosTheta - sunCosAngle) / (1.0f - sunCosAngle + 0.01f));
    if (sunProximity > 0.0f)
    {
        float sunDiskIntensity = smoothstep(0.0f, 1.0f, sunProximity);
        float3 sunColor = float3(1.0f, 0.95f, 0.8f) * SunIntensity * 5.0f;
        skyColor = lerp(skyColor, sunColor, sunDiskIntensity * 0.9f);
    }
    
    if (sunElevation < 0.3f && sunElevation > -0.3f)
    {
        float sunsetFactor = 1.0f - saturate((sunElevation + 0.1f) / 0.4f);
        float3 sunsetColor = float3(1.0f, 0.6f, 0.3f) * sunsetFactor;
        skyColor += sunsetColor * max(0.0f, cosTheta) * sunsetFactor * 0.5f;
    }
    
    float3 minSkyColor = baseSkyColor * 0.1f;
    skyColor = max(skyColor, minSkyColor);
    
    return float4(skyColor, 1.0f);
    
}
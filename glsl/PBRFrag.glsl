// Copyright 2015 Brandon Ly all rights reserved.
//
// Fragment shader.
//
precision highp float;

const float PI = 3.1415927;

// Uniforms
uniform mat4 UMatModel;
uniform mat4 UMatView;
uniform mat4 UMatMV;
uniform mat4 UMatNormal;

uniform samplerCube UTexCubeEnv;
uniform samplerCube UTexCubeIrradiance;

uniform sampler2D UTextureBaseColor;
uniform sampler2D UTextureNormal;
uniform sampler2D UTextureMetallic;
uniform sampler2D UTextureRoughness;

// Variables passed from vert to pixel
varying vec3 VEnvMapI;
varying vec3 VEnvMapN;

varying vec3 VTextureCoordSkybox;
varying vec2 VVertexTexCoord;

varying vec3 VTanLightDir;
varying vec3 VTanViewDir;

// Gamma decode and correct functions
highp vec4 gammaDecode(vec4 encoded) { return pow(encoded, vec4(2.2)); }
highp vec4 gammaCorrect(vec4 linear) { return pow(linear, vec4(1.0 / 2.2)); }

// Physically-based rendering functions

// Schlick Approximation (of Fresnel Reflectance) (F function),
// with additional parameterization based on metallic such that F0
// is 0.04 for metallic at 0. 
vec3 SchlickApprox(vec3 n, vec3 l, vec3 albedo, float metallic)
{
    vec3 F0 = mix(vec3(0.04), albedo, metallic); // specular color
    return F0 + (1.0 - F0) * pow(1.0 - max(0.0, dot(n, l)), 5.0);
}

// Combined G2 Smith height-correlated masking-shadowing function and
// specular microfacet BRDF denominator (G function)
float SmithG2SpecBRDF(vec3 l, vec3 v, vec3 n, float roughness)
{
    return 0.5 / mix(2.0 * abs(dot(n, l)) * abs(dot(n, v)), abs(dot(n, l)) + abs(dot(n, v)), roughness * roughness);
}

// GGX (Trowbridge & Reitz) Distribution (D function)
float GGX(vec3 n, vec3 m, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float num = (dot(n, m) > 0.0 ? 1.0 : 0.0) * a2;
    float denom = PI * pow(1.0 + pow(dot(n, m), 2.0) * (a2 - 1.0), 2.0);
    return num / denom;
}

// Reflectance Equation - Outgoing Radiance function (Lo)
vec3 RadianceOut(vec3 l, vec3 v, vec3 n, vec3 albedo, float metallic, float roughness)
{
    roughness = clamp(roughness, 0.1, 1.0);

    float NdotL = max(0.0, dot(n, l));

    // Specular Microfacet BRDF calculations
    vec3 h = normalize(l + v); // halfway vector
    vec3 F = SchlickApprox(h, l, albedo, metallic);
    float GDenom = SmithG2SpecBRDF(l, v, n, roughness);
    float D = GGX(n, h, roughness);

    // Specular BRDF
    vec3 BRDFSpecular = F * GDenom * D;

    // Diffuse Lambertian BRDF, with additional parameterization that sets the
    // albedo to just black if fully metal.
    vec3 BRDFDiffuse = albedo / vec3(PI) * (1.0 - F);

    vec3 DiffuseIrradiance = textureCube(UTexCubeIrradiance, VEnvMapN).rgb * BRDFDiffuse;

    return (BRDFDiffuse + BRDFSpecular) * NdotL + DiffuseIrradiance;
}

// Main entry point for pixel shader
void main(void)
{
    // Normal map
    vec3 normalMap = texture2D(UTextureNormal, VVertexTexCoord).rgb;
    vec3 TanNormalDir = normalize(normalMap * 2.0 - 1.0);

    // Add environment mapping.
    vec3 EnvMapR = reflect(VEnvMapI, VEnvMapN);
    vec4 ColorEnvMap = textureCube(UTexCubeEnv, EnvMapR);

    // Gamma uncorrect
    vec4 ColorBase = gammaDecode(texture2D(UTextureBaseColor, VVertexTexCoord));

    vec3 ColorDirLight = vec3(1.0);
    float Metallic = texture2D(UTextureMetallic, VVertexTexCoord).r;
    float Roughness = texture2D(UTextureRoughness, VVertexTexCoord).r;

    // Metallic = 0.0;
    // Roughness = 1.0;

    vec4 Color = vec4(0.0);
    Color.rgb = RadianceOut(VTanLightDir, VTanViewDir, TanNormalDir, ColorBase.rgb, Metallic, Roughness);
    Color.rgb *= ColorDirLight;

    Color = clamp(Color, 0.0, 1.0); // Clamp to RGB color range

    Color = gammaCorrect(Color); // gamma correct
    Color.a = 1.0;

    gl_FragColor = Color;
}

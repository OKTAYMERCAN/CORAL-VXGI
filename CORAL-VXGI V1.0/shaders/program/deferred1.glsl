/*
=====================================================================
  program/deferred1.glsl - ZAMANSAL BİRİKTİRME
=====================================================================
  Gürültülü GI'yı önceki karelerle ortalar:
    1. Bu pikselin dünya konumunu, önceki karenin kamerasıyla ekrana
       yansıtır ("yeniden projeksiyon") -> geçen karede nerede görünüyordu?
    2. Oradaki geçmişi okur. Derinlik tutmuyorsa (nesne yeni ortaya
       çıktıysa) geçmişi atar.
    3. Yeni örneği 1/kareSayısı ağırlığıyla karıştırır.
  Çıktılar (her ikisi de kareler arasında korunur):
    colortex4: rgb = biriktirilmiş GI, a = biriken kare sayısı
    colortex7: bu karenin doğrusal derinliği (bir sonraki kare için)
=====================================================================
*/
#include "/lib/settings.glsl"
#include "/lib/pipeline.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/space.glsl"

#ifdef VERTEX_SHADER
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
#endif

#ifdef FRAGMENT_SHADER

in vec2 texcoord;

uniform sampler2D colortex2; // malzeme
uniform sampler2D colortex3; // bu karenin ham GI'si
uniform sampler2D colortex4; // GI geçmişi
uniform sampler2D colortex7; // önceki karenin derinliği
uniform sampler2D depthtex0;

/* RENDERTARGETS: 4,7 */
layout(location = 0) out vec4 outHistory;
layout(location = 1) out vec4 outLinearDepth;

void main() {
    ivec2 px = ivec2(gl_FragCoord.xy);
    float depth = texelFetch(depthtex0, px, 0).r;
    int material = int(texelFetch(colortex2, px, 0).r * 255.0 + 0.5);

    if (depth >= 1.0 || material == MAT_UNLIT || material == MAT_HAND) {
        outHistory = vec4(0.0);
        outLinearDepth = vec4(0.0);
        return;
    }

    vec3 current = texelFetch(colortex3, px, 0).rgb;
    vec3 viewPos = screenToView(texcoord, depth);
    float linDepth = -viewPos.z;
    vec3 playerPos = viewToPlayer(viewPos);

    // Önceki karede bu nokta ekranın neresindeydi?
    vec3 prevPlayer = playerPos + (cameraPosition - previousCameraPosition);
    vec3 prevView = mat3(gbufferPreviousModelView) * prevPlayer + gbufferPreviousModelView[3].xyz;
    vec4 prevClip = gbufferPreviousProjection * vec4(prevView, 1.0);
    vec2 prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
    float expectedDepth = -prevView.z;

    vec4 history = vec4(0.0);
    float weightSum = 0.0;

    if (prevClip.w > 0.0 && all(greaterThan(prevUV, vec2(0.0))) && all(lessThan(prevUV, vec2(1.0)))) {
        vec2 res = vec2(viewWidth, viewHeight);
        vec2 pix = prevUV * res - 0.5;
        ivec2 base = ivec2(floor(pix));
        vec2 f = fract(pix);
        float tolerance = expectedDepth * GI_TEMPORAL_DEPTH_TOLERANCE + 0.08;

        // Çift doğrusal (bilinear) okuma, ama her komşu ayrı ayrı derinlik testinden geçer.
        // Böylece nesne kenarlarında arka plan geçmişi öne sızmaz.
        for (int y = 0; y <= 1; y++) {
            for (int x = 0; x <= 1; x++) {
                ivec2 p = clamp(base + ivec2(x, y), ivec2(0), ivec2(res) - 1);
                float w = (x == 1 ? f.x : 1.0 - f.x) * (y == 1 ? f.y : 1.0 - f.y);
                float prevDepth = texelFetch(colortex7, p, 0).r;
                if (abs(prevDepth - expectedDepth) < tolerance) {
                    history += texelFetch(colortex4, p, 0) * w;
                    weightSum += w;
                }
            }
        }
    }

    vec3 histColor = current;
    float frames = 0.0;
    if (weightSum > 0.05) {
        history /= weightSum;
        histColor = history.rgb;
        frames = history.a;
    }
    // Bozuk değer koruması: bir NaN geçmişe girerse sonsuza kadar kalır
    if (any(isnan(histColor)) || any(isinf(histColor))) {
        histColor = current;
        frames = 0.0;
    }

    frames = min(frames + 1.0, float(GI_TEMPORAL_FRAMES));
    vec3 accumulated = mix(histColor, current, 1.0 / frames);

    outHistory = vec4(accumulated, frames);
    outLinearDepth = vec4(linDepth, 0.0, 0.0, 1.0);
}

#endif

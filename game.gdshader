shader_type spatial;

// Pass your Texture2DArray containing all 6 textures in order (0 to 5)
uniform sampler2DArray terrain_textures : source_color, filter_linear_mipmap_anisotropic;
uniform float texture_scale = 10.0;
uniform float patch_scale = 0.05;
uniform float blend_hardness : hint_range(0.01, 0.2) = 0.05; // Lower values = smoother transitions

// Deterministic noise generator to run asset-free math
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0,0.0)), hash(i + vec2(1.0,0.0)), f.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0,1.0)), f.x), f.y);
}

void fragment() {
    // 1. Map tiling scale for the texture visuals
    vec2 texture_uv = UV * texture_scale;
    
    // 2. Sample procedural continuous noise (ranges perfectly from 0.0 to 1.0)
    float noise = value_noise(UV * patch_scale);
    
    // 3. Define the precise cumulative thresholds based on your target percentages
    float t_grass  = 0.40;
    float t_tall   = 0.40 + 0.10; // 0.50
    float t_flower = 0.50 + 0.08; // 0.58
    float t_dirt   = 0.58 + 0.10; // 0.68
    float t_rocks  = 0.68 + 0.07; // 0.75
    
    // Variables to track our primary texture layer and its neighbor for smooth edge blending
    float current_layer = 0.0;
    float next_layer = 0.0;
    float weight = 0.0;
    
    // 4. Bracket system to determine texture allocation based on your targets
    if (noise < t_grass) {
        current_layer = 0.0; // Grass
        next_layer = 1.0;
        weight = smoothstep(t_grass - blend_hardness, t_grass, noise);
    } else if (noise < t_tall) {
        current_layer = 1.0; // Tall Grass
        next_layer = 2.0;
        weight = smoothstep(t_tall - blend_hardness, t_tall, noise);
    } else if (noise < t_flower) {
        current_layer = 2.0; // Flower Grass
        next_layer = 3.0;
        weight = smoothstep(t_flower - blend_hardness, t_flower, noise);
    } else if (noise < t_dirt) {
        current_layer = 3.0; // Dirt
        next_layer = 4.0;
        weight = smoothstep(t_dirt - blend_hardness, t_dirt, noise);
    } else if (noise < t_rocks) {
        current_layer = 4.0; // Rocks
        next_layer = 5.0;
        weight = smoothstep(t_rocks - blend_hardness, t_rocks, noise);
    } else {
        current_layer = 5.0; // Mixed
        next_layer = 5.0;
        weight = 0.0;
    }
    
    // 5. Query both layers from the Texture2DArray using our scale
    vec4 tex_a = texture(terrain_textures, vec3(texture_uv, current_layer));
    vec4 tex_b = texture(terrain_textures, vec3(texture_uv, next_layer));
    
    // 6. Blend them together at the boundaries so it doesn't look like harsh pixels
    ALBEDO = mix(tex_a, tex_b, weight).rgb;
}

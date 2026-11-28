shader_type canvas_item;
uniform sampler2D grass : repeat_enable, filter_linear_mipmap;
uniform sampler2D earth : repeat_enable, filter_linear_mipmap;
uniform sampler2D track : repeat_enable, filter_linear_mipmap;
uniform sampler2D water_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D masks : filter_linear, repeat_disable;
uniform vec2 world_size;
void fragment(){
	vec2 p=UV*world_size;
	vec3 mask=texture(masks,UV).rgb;
	vec2 uv=p/320.0;
	vec3 c=mix(texture(grass,uv).rgb,texture(earth,uv).rgb,mask.r*0.92);
	c=mix(c,texture(water_tex,uv).rgb*vec3(.65,.88,1.),smoothstep(.22,.75,mask.b));
	c=mix(c,texture(track,uv).rgb,smoothstep(.16,.75,mask.g));
	COLOR=vec4(c,1.);
}

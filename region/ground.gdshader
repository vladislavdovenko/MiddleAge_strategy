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
	float channel=smoothstep(.24,.68,mask.g);
	float grain=texture(water_tex,uv+vec2(TIME*.013,0.)).r;
	float wave=sin(p.y*.24+sin(p.x*.043+TIME)*1.7+TIME*1.8);
	vec3 water=mix(vec3(.19,.39,.40),vec3(.28,.51,.55),grain);
	water+=vec3(.18,.21,.18)*smoothstep(.90,1.,wave)*(.35+.65*grain);
	c=mix(c,vec3(.58,.55,.36),smoothstep(.17,.37,mask.g));
	c=mix(c,water,channel);
	COLOR=vec4(c,1.);
}

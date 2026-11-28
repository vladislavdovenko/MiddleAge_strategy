shader_type canvas_item;
uniform float angle = 0.0;
void fragment(){
	vec2 uv = UV;
	vec2 center = vec2(0.197,0.630);
	vec2 radius = vec2(0.157,0.36);
	vec2 p = (uv-center)/radius;
	float r=length(p);
	if(r>0.23 && r<0.83){
		float a=angle*smoothstep(0.23,0.30,r)*(1.0-smoothstep(0.74,0.83,r));
		uv=center+radius*vec2(cos(a)*p.x-sin(a)*p.y,sin(a)*p.x+cos(a)*p.y);
	}
	COLOR=texture(TEXTURE,uv);
}

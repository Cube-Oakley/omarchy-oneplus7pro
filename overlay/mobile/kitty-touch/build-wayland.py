import os
import setup as s
os.makedirs('build', exist_ok=True)
a = s.Options()
a.link_time_optimization = False
s.init_env_from_args(a)
g = s.glfw.init_env(s.env, s.pkg_config, s.pkg_version, s.at_least_version, s.test_compile, 'wayland')
s.glfw.build_wayland_protocols(g, s.parallel_run, s.emphasis, s.newer, 'glfw')
with s.CompilationDatabase() as db:
    s.compile_c_extension(g, 'kitty/glfw-wayland', db,
        [os.path.join('glfw', x) for x in g.sources],
        [os.path.join('glfw', x) for x in g.all_headers])
    db.build_all()

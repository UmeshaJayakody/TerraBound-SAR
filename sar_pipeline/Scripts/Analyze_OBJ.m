function a = Analyze_OBJ(path, progress)
% Reads an .obj file of any size and works out what it is: which way is up,
% what its units are, how big it is (see Analyze_Mesh). The window calls this
% once per file when an object is chosen, and Resolve_Model then applies the
% user's own choices, if any, without reading the file again.
%
% path:     the .obj file
% progress: optional function handle f(text)
%
% Returns what Analyze_Mesh returns, plus a.info from Read_OBJ.

if nargin < 2, progress = []; end
[V, tri, info] = Read_OBJ(path, progress);
a = Analyze_Mesh(V, tri, info.header, info.bytes);
a.info = info;
a.file = path;
d = dir(path);
a.stamp = [d(1).bytes d(1).datenum];
end

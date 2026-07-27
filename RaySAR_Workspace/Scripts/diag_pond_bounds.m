R = load('D:/FYP/RaySAR_Workspace/POV_Ray/RaySAR/Contributions.txt');
az = sort(R(:,1)); ra = sort(R(:,2));
pct = @(v,p) v(max(1, min(numel(v), round(p/100*numel(v)))));
for p = [0.5 1 2 5 10 25 50 75 90 95 98 99 99.5]
    fprintf('p%-5g az=%10.3f  ra=%10.3f\n', p, pct(az,p), pct(ra,p));
end

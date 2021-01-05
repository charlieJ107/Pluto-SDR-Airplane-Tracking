function address = FindPluto()
%% 检查Pluto在不在，不在就报错，在的话返回pluto的地址
if isempty(which('plutoradio.internal.getRootDir'))
  msg = message('comm_demos:common:NoSupportPackage', ...
    'Communications Toolbox Support Package for ADALM-PLUTO Radio', ...
    ['<a href="https://www.mathworks.com/hardware-support/' ...
    'pluto.html">ADALM-PLUTO Radio Support From Communications Toolbox</a>']);
  error(msg);
end

try
  plutoRadios = findPlutoRadio();
catch
  plutoRadios = {};
end

radioCnt = length(plutoRadios);
address = cell(radioCnt,1);
for p=1:length(plutoRadios)
  radioCnt = radioCnt + 1;
  address{p} = plutoRadios(p).RadioID;
end
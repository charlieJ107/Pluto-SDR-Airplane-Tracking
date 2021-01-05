classdef (StrictDefaults)RxSync < matlab.System & matlab.system.mixin.Propagates & matlab.system.mixin.CustomIcon
%% 数据包同步器
% 接收到的信号中搜索数据包并且返回同步后的数据包的抽样
% 最主要的就是那个step函数
% [packet, count, delay] = step(parser, x)
% 这个函数会在信号中搜索符合ads-b协议的数据组, count返回组的数量
% packet是接收到的采样的矩阵, st是抽样的延迟值, 表示packet中每个组相对于x开始时的接收时间

properties (Nontunable) % 所需要的参数
    ADSBParameters = getConfigParam();
end

properties (Access = private)%私有对象
    Buffer % 缓冲区
    Filter % 滤波器
end

% 构造函数
methods
    function obj = RxSync(varargin)
        setProperties(obj, nargin, varargin{:}, 'ADSBParameters');
    end
end

    methods (Access = protected)
        
        % 初始化原有对象
        function setupImpl(obj, ~)
            adsbParam = obj.ADSBParameters;
            
            % 初始化缓冲区， 大小的计算利用了之前算出来过的
            % 每帧的采样数等参数
            obj.Buffer = zeros( ...
                (adsbParam.SamplesPerFrame * adsbParam.InterpolationFactor) ...
                + adsbParam.MaxPacketLength, 1);
            % 利用之前设计的滤波器参数来设计一个FIR滤波器，放进私有对象里
            obj.Filter = dsp.FIRFilter('Numerator', adsbParam.SyncFilter');
            
        end
        
        function [packetSamples, packetCount, SyncTimeVector] = stepImpl(obj, x)
            adsbParam = obj.ADSBParameters;
            
            % 把信号缓存下来，以便处理头尾的包
            olapLength = adsbParam.MaxPacketLength;
            obj.Buffer(1 : olapLength) = obj.Buffer((end-olapLength+1):end);
            obj.Buffer((end-numel(x)+1):end) = x;
            xBuff = obj.Buffer;
            
            % 将同步序列正交化
            xFilt = obj.Filter(xBuff(1:adsbParam.SyncDownSampleFactor:end));
            
            % 查找数据包
            [packetSamples, packetCount, SyncTimeVector]=...
                searchPacket(xFilt, xBuff,adsbParam);
            
        end
        
     function s = saveObjectImpl(obj)
      % Set properties in structure s to values in object obj

      % Set public properties and states
      s = saveObjectImpl@matlab.System(obj);

      % Set private and protected properties
      s.Buffer = obj.Buffer;
      s.Filter = obj.Filter;
    end

    function loadObjectImpl(obj,s,wasLocked)
      % Set properties in object obj to values in structure s

      % Set private and protected properties
      if ~isequal(class(s.Buffer),'dsp.Buffer')
          % Preserve contents of saved Buffer property
          obj.Buffer = s.Buffer;
      else
          % Backward compatibility (saved before R2019b):
          % reset buffer to all zeros, not using dsp.Buffer
          adsbParam  = s.ADSBParameters;
          obj.Buffer = zeros( ...
              (adsbParam.SamplesPerFrame*adsbParam.InterpolationFactor) ...
              + adsbParam.MaxPacketLength, 1); % MaxPacketLength overlap
      end
      obj.Filter = s.Filter;

      % Set public properties and states
      loadObjectImpl@matlab.System(obj,s,wasLocked);
    end

    function flag = isInputSizeLockedImpl(~,~)
      % Return true if input size is not allowed to change while
      % system is running
      flag = true;
    end

    function [sz1,sz2,sz3] = getOutputSizeImpl(obj)
      % Return size for each output port
      adsbParam = obj.ADSBParameters;
      sz1 = [adsbParam.LongPacketLength adsbParam.MaxNumPacketsInFrame];
      sz2 = [1 1];
      sz3 = [adsbParam.MaxNumPacketsInFrame 1];
    end

    function [dt1,dt2,dt3] = getOutputDataTypeImpl(~)
      % Return data type for each output port
      dt1 = 'single';
      dt2 = 'double';
      dt3 = 'double';
    end

    function [cp1,cp2,cp3] = isOutputComplexImpl(~)
      % Return true for each output port with complex data
      cp1 = false;
      cp2 = false;
      cp3 = false;
    end

    function [fs1,fs2,fs3] = isOutputFixedSizeImpl(~)
      % Return true for each output port with fixed size
      fs1 = true;
      fs2 = true;
      fs3 = true;
    end
    
    function icon = getIconImpl(~)
      icon = sprintf('ADS-B\nPacket\nSynchronizer');
    end

    function name1 = getInputNamesImpl(~)
      name1 = 'x';
    end

    function [name1,name2,name3] = getOutputNamesImpl(~)
      % Return output port names for System block
      name1 = 'pkt';
      name2 = 'pktCnt';
      name3 = 'Tsync';
    end
    end

  methods(Static, Access = protected)
    function header = getHeaderImpl
      % Define header panel for System block dialog
      header = matlab.system.display.Header('Mode-S packet synchronizer');
    end

    function group = getPropertyGroupsImpl
      % Define property section(s) for System block dialog
      group = matlab.system.display.Section('Mode-S packet synchronizer');
    end
  end
end

            
            
            
            
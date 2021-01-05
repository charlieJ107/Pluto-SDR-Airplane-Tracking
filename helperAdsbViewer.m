classdef helperAdsbViewer < handle
  %ADSBViewer ADS-B message viewer
  %   V = helperAdsbViewer creates a Mode-S message viewer object that
  %   processes message packets to be displayed on GUI, map, and saved in a
  %   text file.
  %
  %   helperAdsbViewer methods:
  %
  %   update(V,MSG,CNT,LOST) displays the contents of the Mode-S messages
  %   in the message vector, MSG. CNT is the number of valid messages in
  %   MSG. LOST is a flag if there are any lost samples.
  %  
  %   startDataLog(V) starts data logging to a text file.
  %
  %   startMapUpdate(V) starts map updates.
  %
  %   start(V) starts message viewer, V. V captures the absolute start
  %   time, which is used to calculate the absolute reception time of each
  %   packet. Once started, message viewer updates the GUI every second
  %   and, if launched, the map every 10 seconds.
  %
  %   stop(V) stops message viewer, V.
  %
  %   See also ADSBExample, helperAdsbRxPhy.
  
  %   Copyright 2015-2018 The MathWorks, Inc.

  properties
    LogFileName = 'adsb_messages.txt'
    SignalSourceType = ExampleSourceType.Captured;
    RadioAddress = 0;
    Map
    licenseFlag = 0;
  end
  
  properties (Constant,Hidden)
    SquitterHeaderFieldNames = {'Message','Time','CRC','DF','CA',...
      'ICAO24','TC'}
    IdentificationFieldNames = {'VehicleCategory','FlightID'}
    PositionFieldNames = {'Status','DiversityAntenna','Altitude',...
      'UTCSynchronized','Longitude','Latitude'}
    VelocityFieldNames = {'Subtype','IntentChange','IFRCapability',...
      'VelocityUncertainty','Speed',['Heading(' char(176) ')'] ,'HeadingSymbol',...
      'VerticalRateSource','VerticalRate','TurnIndicator','GHD'}
  end
  
  properties (Hidden)
    NumGoodShortSquitter = 0
    NumTotalShortSquitter = 0
    NumGoodExtendedSquitter = 0
    NumTotalExtendedSquitter = 0
    NumOtherModeSPackets = 0
    isInApp = false;
    Lost = 0;
  end
  
  properties (SetAccess = private, Dependent)
    StartTime
    LogData
  end
  
  properties (Access = private)
    RawStartTime = 0
    TableData
    FileHandle = -1
    FigureHandle = -1
    ParentHandle = -1
    LaunchMapvalue = 0
    LogDatavalue = 0
    GUIHandles
    FieldsToShow = {'Current', 'ICAO24', 'FlightID', 'Latitude', ...
      'Longitude', 'Altitude', 'Speed', 'Heading', 'VerticalRate', 'Time'}
    FieldsToShowIndices
    ProgressBar
    pDispStr
  end

  properties (Access = private, Dependent)
    MapPlanes
  end

  properties (Constant, Access = private)
    MaxNumMessages = 15
    
    MapZoomLevel = 10
    
    CheckMark = char(10003)
  end
  
  methods
    function obj = helperAdsbViewer(varargin)
      p = inputParser;
      addParameter(p, 'SignalSourceType', ExampleSourceType.Captured);
      addParameter(p,'LogFileName','adsb_messages.txt');
      addParameter(p,'ParentHandle',-1);
      addParameter(p, 'isInApp', false);
      parse(p,varargin{:});
      obj.LogFileName = p.Results.LogFileName;
      obj.SignalSourceType = p.Results.SignalSourceType;
      obj.ParentHandle = p.Results.ParentHandle;
      obj.isInApp = p.Results.isInApp;
      
      renderGUI(obj);
      
      reset(obj);
      
      [~,dataFieldNames] = enumeration('ADSBFieldNames');
      for p=1:length(obj.FieldsToShow)
        obj.FieldsToShowIndices(p) = ...
          find(strcmpi(obj.FieldsToShow{p}, dataFieldNames));
      end
    end
    
    function start(obj)
      setStartTime(obj);
      startProgressBar(obj)
    end
    
    function stop(obj)
      stopProgressBar(obj)
      stopDataLog(obj)
      stopMapUpdate(obj)
      % Flush map data
      updateMap(obj);
      obj.licenseFlag = 0;
    end
    
    function reset(obj)
      [~,dataFieldNames] = enumeration('ADSBFieldNames');
      obj.TableData = repmat({''},...
        obj.MaxNumMessages,length(dataFieldNames));
      for p=1:obj.MaxNumMessages
        obj.TableData{p,ADSBFieldNames.Time} = 0;
      end

      initMapInfo(obj);
      
      obj.NumGoodShortSquitter = 0;
      obj.NumTotalShortSquitter = 0;
      obj.NumGoodExtendedSquitter = 0;
      obj.NumTotalExtendedSquitter = 0;
      obj.NumOtherModeSPackets = 0;
      obj.Lost = 0;
    end
    
    function setStartTime(obj)
      obj.RawStartTime = now;
    end
    
    function value = get.StartTime(obj)
      value = datestr(obj.RawStartTime);
    end
    
    function flag = isStopped(obj)
      if isvalid(obj.GUIHandles.ProgressIndicator) && ...
          strcmp(obj.GUIHandles.ProgressIndicator.String, 'Stopped')
        flag = true;
      else
        flag = false;
      end
    end

    function startProgressBar(obj)
      obj.GUIHandles.ProgressIndicator.String  = 'Receiving';
      start(obj.ProgressBar.Timer)
      drawnow;
    end

    function stopProgressBar(obj)
      obj.GUIHandles.ProgressIndicator.String  = getString(message('comm_demos:common:ProgressBarStopped'));
      stop(obj.ProgressBar.Timer)
      drawnow;
    end

    function startSourceStatus(obj)
        sigSrcType = obj.SignalSourceType;
        if strcmp(sigSrcType, 'Captured')
            dispStr = 'Selected file reader as the signal source';
        elseif strcmp(sigSrcType, 'RTLSDRRadio') || strcmp(sigSrcType,'PlutoSDRRadio')
            dispStr = 'Checking radio connections...';
            count = 0;
            switch count
                case 0
                    obj.GUIHandles.ProgressIndicator.String = obj.pDispStr;
                case 1
                    obj.GUIHandles.ProgressIndicator.String = ...
                        [obj.pDispStr '.'];
                case 2
                    obj.GUIHandles.ProgressIndicator.String = ...
                        [obj.pDispStr '..'];
                case 3
                    obj.GUIHandles.ProgressIndicator.String = ...
                        [obj.pDispStr '...'];
                case 4
                    obj.GUIHandles.ProgressIndicator.String = ...
                        [obj.pDispStr '....'];
                case 5
                    obj.GUIHandles.ProgressIndicator.String = ...
                        [obj.pDispStr '.....'];
            end

            count = count + 1;
            count = mod(count,6);

            obj.ProgressBar.Count = count;
            drawnow
        end
        obj.GUIHandles.ProgressIndicator.String  = dispStr;
        obj.pDispStr = dispStr;
        drawnow;
    end

    function stopSourceStatus(obj)
      sigSrcType = obj.SignalSourceType;
      if strcmp(sigSrcType, 'Captured')
          dispStr = 'Selected signal source: File';
      elseif strcmp(sigSrcType, 'RTLSDRRadio') % RTL-SDR radio
          dispStr = ['Connected to RTL-SDR with radio address: ',obj.RadioAddress];
      elseif strcmp(sigSrcType, 'PlutoSDRRadio') % ADALM-PLUTO radio
          dispStr = ['Connected to ADALM-PLUTO with radio address: ',obj.RadioAddress];
      end
      obj.GUIHandles.ProgressIndicator.String  = dispStr;
      obj.pDispStr = dispStr;
      drawnow;
    end

    function radioConfigStatus(obj)
        sigSrcType = obj.SignalSourceType;
        if ~strcmp(sigSrcType, 'Captured')
            dispStr = 'Configuring radio parameters...';
            obj.GUIHandles.ProgressIndicator.String  = dispStr;
            obj.pDispStr = dispStr;
            drawnow;
        end
    end

    function closeGUI(obj)
      if ishandle(obj.FigureHandle) && isvalid(obj.FigureHandle)
        close(obj.FigureHandle)
      end
    end
    
    function value = get.LogData(obj)
      value = obj.LogDatavalue;
    end
    
    function set.LogData(obj, value)
      obj.LogDatavalue = value;
    end
    
    function value = get.MapPlanes(obj)
      value = obj.LaunchMapvalue;
    end
    
    function update(obj, msg, msgCnt, lost)
      if msgCnt > 0
        updatePlaneData(obj, msg, msgCnt);
        updateRadioStatus(obj, lost);
        updateGUI(obj);
        if obj.LogData
          write2File(obj, msg, msgCnt);
        end
      end
    end
    
    function startDataLog(obj,logfilename)
        % Check if the file is already open
        if nargin == 1
        fileName = fopen(obj.FileHandle);
        if ~strcmp(fileName, obj.LogFileName)
          obj.FileHandle = fopen(obj.LogFileName,'w');
          if obj.FileHandle ~= -1
            obj.LogData = true;
            fprintf(obj.FileHandle, ['Message, CRC, Time, DF, CA, ICAO24, TC, ', ...
              'Vehicle Category, Flight ID, ', ...
              'Status, Antenna, Altitude, UTC Sync, CPR Format, Latitude, ', ...
              'Longitude, Subtype, Intent Change, IFR Capability, ', ...
              'Velocity Uncertainty, Speed, Heading(' char(176) '), Heading, ', ...
              'Vertical Rate, Turn Indicator, GHD\n']);
          else
            error(message('comm_demos:common:LogFileNotOpened',obj.LogFileName))
          end
        end
        elseif nargin == 2
        obj.LogFileName = logfilename;
        fileName = fopen(obj.FileHandle);
        if ~strcmp(fileName, obj.LogFileName)
          obj.FileHandle = fopen(obj.LogFileName,'w');
          if obj.FileHandle ~= -1
            obj.LogData = true;
            fprintf(obj.FileHandle, ['Message, CRC, Time, DF, CA, ICAO24, TC, ', ...
              'Vehicle Category, Flight ID, ', ...
              'Status, Antenna, Altitude, UTC Sync, CPR Format, Latitude, ', ...
              'Longitude, Subtype, Intent Change, IFR Capability, ', ...
              'Velocity Uncertainty, Speed, Heading(' char(176) '), Heading, ', ...
              'Vertical Rate, Turn Indicator, GHD\n']);
          else
            error(message('comm_demos:common:LogFileNotOpened',obj.LogFileName))
          end
        end
        end
    end
    
    function stopDataLog(obj)
      fileName = fopen(obj.FileHandle);
      if strcmp(fileName, obj.LogFileName)
        fclose(obj.FileHandle);
        obj.LogData = false;
      end
    end
    
    function success = launchMap(obj)
      if exist('wmcenter', 'file') && license('checkout', 'MAP_Toolbox')
        if ~isa(obj.Map.Handle, 'map.webmap.Canvas') ...
            || ~isvalid(obj.Map.Handle)
        
          % Create a timer object to periodically update the map
          obj.Map.Timer = timer(...
            'BusyMode', 'drop', ...
            'ExecutionMode', 'fixedRate', ...
            'Name', 'MapUpdate', ...
            'ObjectVisibility', 'off', ...
            'Period', 20, ...
            'StartDelay', 1, ...
            'TimerFcn', @obj.updateMap);
          
          % Open default map
          obj.Map.Handle = webmap;
          addlistener(obj.Map.Handle, 'ObjectBeingDestroyed', ...
              @(src,event)closeMapCallback(obj, ...
              obj.Map.Timer));
          
          % Check if we have any planes with airborne position information
          tableData = obj.TableData;
          meanLat = 0;
          meanLon = 0;
          cnt = 0;
          for idx = 1:obj.MaxNumMessages
            if isa(tableData{idx,ADSBFieldNames.Latitude},'double')
              if ~isnan(tableData{idx,ADSBFieldNames.Latitude})
                meanLat = meanLat + tableData{idx,ADSBFieldNames.Latitude};
                meanLon = meanLon + tableData{idx,ADSBFieldNames.Longitude};
                cnt = cnt + 1;
              end
            end
          end
          if cnt > 0
            wmcenter(meanLat/cnt, meanLon/cnt, obj.MapZoomLevel);
          end

          obj.LaunchMapvalue = 1;

          start(obj.Map.Timer);
        end
        success = true;
      else
        success = false;
        msgbox(...
          'This feature requires a valid license for Mapping Toolbox', ...
          'ADS-B Aircraft Tracking','modal')
      end
    end
    
    function closeMap(obj)
      if exist('wmcenter', 'file') && license('checkout', 'MAP_Toolbox')
        if isa(obj.Map.Handle, 'map.webmap.Canvas') ...
            && isvalid(obj.Map.Handle)
          wmclose(obj.Map.Handle)
          obj.Map.FirstPlane = false;
          obj.Map.MarkerData = zeros(obj.MaxNumMessages, 2);
        end
      end
    end
    
    function startMapUpdate(obj)
      success = launchMap(obj);
      if success && strcmp(obj.Map.Timer.Running, 'off')
        start(obj.Map.Timer);
      end
    end
    
    function stopMapUpdate(obj)
      if isa(obj.Map.Timer, 'timer') && isvalid(obj.Map.Timer) ...
          && strcmp(obj.Map.Timer.Running, 'on')
        stop(obj.Map.Timer);
      end
    end
    
    function delete(obj)
      if ishandle(obj.FigureHandle) && isvalid(obj.FigureHandle)
        close(obj.FigureHandle)
      end
    end
  end
  
  methods (Access = private)
    function updateGUI(obj)
      if ~isa(obj.FigureHandle, 'matlab.ui.Figure') ...
          || ~isvalid(obj.FigureHandle)
        renderGUI(obj);
        startProgressBar(obj);
      end
      
      tableData = obj.TableData;
      
      good = obj.NumGoodExtendedSquitter;
      total = obj.NumTotalExtendedSquitter;
      obj.GUIHandles.LongMessagesDet.String = int2str(total);
      obj.GUIHandles.LongMessagesDecod.String = int2str(good);
      obj.GUIHandles.LongMessagesPER.String = ...
        sprintf('%3.1f',100*(total-good)/total);

      good = obj.NumGoodShortSquitter;
      total = obj.NumTotalShortSquitter;
      obj.GUIHandles.ShortMessagesDet.String = int2str(total);
      obj.GUIHandles.ShortMessagesDecod.String = int2str(good);
      obj.GUIHandles.ShortMessagesPER.String = ...
        sprintf('%3.1f',100*(total-good)/total);
      
      total = obj.NumOtherModeSPackets;
      obj.GUIHandles.OtherMessagesDet.String = int2str(total);
      obj.GUIHandles.OtherMessagesDecod.String = 'N/A';
      obj.GUIHandles.OtherMessagesPER.String = 'N/A';
      
      if any(~strncmp(tableData(:,ADSBFieldNames.Current),'',1))
        % If there is updated data in the table
        for idx = 1:obj.MaxNumMessages
          if strncmp(tableData{idx,ADSBFieldNames.ICAO24},  '',1)
            tableData{idx,ADSBFieldNames.Time} = '';
          else
            tableData{idx,ADSBFieldNames.Time} = ...
              datestr(double(tableData{idx,ADSBFieldNames.Time}),'HH:MM:SS');
          end
        end
        
        newTableData = tableData(:,obj.FieldsToShowIndices);
        
        obj.GUIHandles.DataTable.Data = newTableData;
      end
    end
    
    function updateRadioStatus(obj, lost)
      if ~isa(obj.FigureHandle, 'matlab.ui.Figure') ...
          || ~isvalid(obj.FigureHandle)
        renderGUI(obj);
        startProgressBar(obj);
      end
      obj.Lost = lost;
    end
    
    function renderGUI(obj)
      if ~ishandle(obj.ParentHandle) || ~isvalid(obj.ParentHandle)
        obj.FigureHandle = figure('Position', [100 100 990 516], ...
          'Visible', 'off', ...
          'HandleVisibility', 'on', ...
          'Color', [0.8 0.8 0.8], ...
          'MenuBar', 'none', ...
          'Name', 'ADS-B Aircraft Tracking', ...
          'IntegerHandle', 'off', ...
          'NumberTitle', 'off', ...
          'Tag', 'ADS-B Aircraft Tracking');
        movegui(obj.FigureHandle, 'center')
        obj.ParentHandle = uicontainer(obj.FigureHandle);
      else
        obj.FigureHandle = ancestor(obj.ParentHandle, 'figure');
      end
      
      % Set the object handle
      setappdata(obj.FigureHandle, 'ViewerHandle', obj);
      
      % Create main container
      hMain = uicontainer('Parent', obj.ParentHandle);
      
      % (1) Create the main grid
      hGridMain = siglayout.gridbaglayout(hMain);
      hGridMain.VerticalGap = 15;
      hGridMain.HorizontalGap = 5;
      hGridMain.VerticalWeights = [0 1 0 0];
      
       % (1.4) Create container for progress bar
      hProgressBarContainer = uicontainer(obj.ParentHandle);
      add(hGridMain, hProgressBarContainer, ...
        4, 1, ...
        'Fill', 'Both', ...
        'MinimumHeight', 20);

      % Create grid of the progress bar container
      hProgressBarContainerGrid = ...
        siglayout.gridbaglayout(hProgressBarContainer);
      hProgressBarContainerGrid.VerticalGap = 1;
      hProgressBarContainerGrid.HorizontalGap = 1;
      hProgressBarContainerGrid.HorizontalWeights = 1;

      % (1.4.1) Create container for progress bar indicator
      hProgressBarIndicatorContainer = ...
        uicontainer(hProgressBarContainer);
      add(hProgressBarContainerGrid, hProgressBarIndicatorContainer, ...
        1, 1, ...
        'Fill', 'Both', ...
        'MinimumHeight', 20, ...
        'MinimumWidth', 230);

      % Create grid of the progress bar indicator container
      hProgressBarIndicatorContainerGrid = ...
        siglayout.gridbaglayout(hProgressBarIndicatorContainer);
      hProgressBarIndicatorContainerGrid.VerticalGap = 1;
      hProgressBarIndicatorContainerGrid.HorizontalGap = 1;
      hProgressBarIndicatorContainerGrid.VerticalWeights = 1;

      % (1.4.1.1) Progress bar indicator
      obj.GUIHandles.ProgressIndicator = ...
        uicontrol(hProgressBarIndicatorContainer, ...
        'Style', 'text', ...
        'String', 'Stopped', ...
        'HorizontalAlignment', 'left', ...
        'ForegroundColor', 'blue', ...
        'Tag', 'ProgressBarIndicator');
      add(hProgressBarIndicatorContainerGrid, ...
        obj.GUIHandles.ProgressIndicator, ...
        1, 1, ...
        'Fill', 'Both', ...
        'MinimumHeight', obj.GUIHandles.ProgressIndicator.Extent(4), ...
        'MinimumWidth', obj.GUIHandles.ProgressIndicator.Extent(3));
    
      % (1.3) Lost flag
      hLateLost = uicontainer(obj.ParentHandle);
      
      % Create a grid in 1.3
      hGridLateLost = siglayout.gridbaglayout(hLateLost);
      hGridLateLost.VerticalGap = 1;
      hGridLateLost.HorizontalGap = 5;
      hGridLateLost.HorizontalWeights = [0 0 1];
      
      % (1.3.1) Lost text
      hLostText = uicontrol(hLateLost, ...
        'Style', 'text', ...
        'String', 'Lost Flag:', ...
        'HorizontalAlignment', 'left', ...
        'Tag', 'Lost Text');
      add(hGridMain, hLateLost, 3, 1, ...
        'Fill', 'Both', ...
        'MinimumHeight', hLostText.Extent(4));
      add(hGridLateLost, hLostText, 1, 1, ...
        'Fill', 'Both', ...
        'MinimumWidth', hLostText.Extent(3));
      
      % (1.3.2) Lost value
      obj.GUIHandles.LostFlag = uicontrol(hLateLost, ...
        'Style', 'text', ...
        'String', 'N/A', ...
        'HorizontalAlignment', 'left', ...
        'Tag', 'Lost');
      add(hGridLateLost, obj.GUIHandles.LostFlag, 1, 2, ...
        'Fill', 'Both', ...
        'MinimumWidth', 50);
      
      % (1.3.5) Empty space
      hEmpty = uicontainer(hLateLost);
      add(hGridLateLost, hEmpty, 1, 3, ...
        'Fill', 'Both');
    
      % (1.2) Create data table
      obj.GUIHandles.DataTable = uitable(obj.ParentHandle, ...
        'Data', repmat({'','','','','','','','','',''},15,1), ...
        'ColumnName',...
        {'Last','Aircraft ID','Flight ID',['Latitude(' char(176) ')'],['Longitude(' char(176) ')'],...
        'Altitude(ft)','Speed(kn)',['Heading(' char(176) ')'],...
        'Vertical Rate(ft/min)','Time'},...
        'ColumnWidth',{30,60,60,60,78,69,60,68,114,50},...
        'ColumnFormat', ...
        {'char','char','char','char','char',...
        'char','char','char','char','char'}, ...
        'Tag', 'DataTable');
      add(hGridMain, obj.GUIHandles.DataTable, 2, 1, ...
        'Fill', 'Both');
      % Adjust figure width accordingly
      obj.FigureHandle.Position(3) = ...
        obj.GUIHandles.DataTable.Extent(3)+2*hGridMain.HorizontalGap;
      
      % (1.1) Create Upper panel for packet statistics
      hUpperContainer = uicontainer(obj.ParentHandle);
      add(hGridMain, hUpperContainer, 1, 1, ...
        'Fill', 'Both', ...
        'MinimumHeight', 110);
      
      % Create a grid in 1.1
      hGridUP = siglayout.gridbaglayout(hUpperContainer);
      hGridUP.VerticalGap = 1;
      hGridUP.HorizontalGap = 5;
      hGridUP.HorizontalWeights = [1 0];
      
      % (1.1) Create Packet statistics panel
      hPacketStats = uipanel(hUpperContainer, ...
        'Title', 'Packet statistics');
      add(hGridUP, hPacketStats, 1, 1, ...
        'Fill', 'Both');
      
      % Create a grid in 1.1 for packet statistics
      hGridStats = siglayout.gridbaglayout(hPacketStats);
      hGridStats.VerticalGap = 2;
      hGridStats.HorizontalGap = 5;
      hGridStats.HorizontalWeights = [0 1 1 1];
      hGridStats.VerticalWeights = [1 1 1 1];
      
      % (1.1.1) Empty
      hEmpty = uicontrol(hPacketStats, 'style', 'text');
      add(hGridStats, hEmpty, 1, 1, ...
        'Fill', 'Both', ...
        'TopInset', 20);
      
      % (1.1.2) Create short messages text
      hShortMessagesText = uicontrol(hPacketStats, ...
        'Style', 'text', ...
        'String', 'Short squitter:', ...
        'HorizontalAlignment', 'left', ...
        'Tag', 'Short Message Text');
      add(hGridStats, hShortMessagesText, 2, 1, ...
        'Fill', 'Both', ...
        'TopInset', 3, ...
        'MinimumWidth', hShortMessagesText.Extent(3));
      
      % (1.1.3) Create long messages text
      hLongMessagesText = uicontrol(hPacketStats, ...
        'Style', 'text', ...
        'String', 'Extended squitter:', ...
        'HorizontalAlignment', 'left', ...
        'Tag', 'Long Message Text');
      add(hGridStats, hLongMessagesText, 3, 1, ...
        'Fill', 'Both', ...
        'TopInset', 3, ...
        'MinimumWidth', hLongMessagesText.Extent(3));
      
      % (1.1.4) Create total messages text
      hOtherMessagesText = uicontrol(hPacketStats, ...
        'Style', 'text', ...
        'String', 'Other Mode-S Packets:', ...
        'HorizontalAlignment', 'left', ...
        'Tag', 'Total Message Text');
      add(hGridStats, hOtherMessagesText, 4, 1, ...
        'Fill', 'Both', ...
        'TopInset', 3, ...
        'MinimumWidth', hOtherMessagesText.Extent(3));
      
      % (1.1.5) Create detected text
      hDetectedText = uicontrol(hPacketStats, ...
        'Style', 'text', ...
        'String', 'Detected', ...
        'Tag', 'Detected Text');
      add(hGridStats, hDetectedText, 1, 2, ...
        'Fill', 'Both', 'TopInset', 20);
      
      % (1.1.6) Create short messages detected
      obj.GUIHandles.ShortMessagesDet = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Short Message Detected');
      add(hGridStats, obj.GUIHandles.ShortMessagesDet, 2, 2, ...
        'Fill', 'Both');
      
      % (1.1.7) Create long messages detected
      obj.GUIHandles.LongMessagesDet = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Long Message Detected');
      add(hGridStats, obj.GUIHandles.LongMessagesDet, 3, 2, ...
        'Fill', 'Both');
      
      % (1.1.8) Create other Mode-S messages detected
      obj.GUIHandles.OtherMessagesDet = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Other Message Detected');
      add(hGridStats, obj.GUIHandles.OtherMessagesDet, 4, 2, ...
        'Fill', 'Both');
            
      % (1.1.9) Create decoded text
      hDecodedText = uicontrol(hPacketStats, ...
        'Style', 'text', ...
        'String', 'Decoded', ...
        'Tag', 'Decoded Text');
      add(hGridStats, hDecodedText, 1, 3, ...
        'Fill', 'Both', 'TopInset', 20);
      
      % (1.1.10) Create short messages decoded
      obj.GUIHandles.ShortMessagesDecod = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Short Message Decoded');
      add(hGridStats, obj.GUIHandles.ShortMessagesDecod, 2, 3, ...
        'Fill', 'Both');
      
      % (1.1.11) Create long messages decoded
      obj.GUIHandles.LongMessagesDecod = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Long Message Decoded');
      add(hGridStats, obj.GUIHandles.LongMessagesDecod, 3, 3, ...
        'Fill', 'Both');
      
      % (1.1.12) Create total messages decoded
      obj.GUIHandles.OtherMessagesDecod = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Other Message Decoded');
      add(hGridStats, obj.GUIHandles.OtherMessagesDecod , 4, 3, ...
        'Fill', 'Both');
      
      % (1.1.13) Create PER text
      hPERText = uicontrol(hPacketStats, ...
        'Style', 'text', ...
        'String', 'PER (%)', ...
        'Tag', 'Received Text');
      add(hGridStats, hPERText, 1, 4, ...
        'Fill', 'Both', 'TopInset', 20);
      
      % (1.1.14) Create short messages PER
      obj.GUIHandles.ShortMessagesPER = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Short Message PER');
      add(hGridStats, obj.GUIHandles.ShortMessagesPER, 2, 4, ...
        'Fill', 'Both');
      
      % (1.1.15) Create long messages PER
      obj.GUIHandles.LongMessagesPER = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Long Message PER');
      add(hGridStats, obj.GUIHandles.LongMessagesPER, 3, 4, ...
        'Fill', 'Both');
      
      % (1.1.16) Create long messages PER
      obj.GUIHandles.OtherMessagesPER = uicontrol(hPacketStats, ...
        'Style', 'edit', ...
        'String', '', ...
        'Enable', 'inactive', ...
        'Tag', 'Other Message PER');
      add(hGridStats, obj.GUIHandles.OtherMessagesPER, 4, 4, ...
        'Fill', 'Both');
      
      initProgressBar(obj);
      
      obj.FigureHandle.DeleteFcn = @obj.cleanupGUI;
      
      drawnow;

      obj.FigureHandle.Visible = 'on';
    end
    
    function updatePlaneData(obj, msg, msgCnt)
      if msgCnt > 0
        tableData = obj.TableData;
        updateTable = false;
        checkMark = obj.CheckMark;
        
        % Remove all checks from current message column
        for idx = 1:obj.MaxNumMessages
          tableData{idx,ADSBFieldNames.Current} = '';
        end
        
        for p=1:msgCnt
          currMsg = msg(p);
          header = currMsg.Header;
          
          if header.DF == 11
            % Short squitter
            obj.NumTotalShortSquitter = obj.NumTotalShortSquitter + 1;
            if header.CRCError == false
              obj.NumGoodShortSquitter = obj.NumGoodShortSquitter + 1;
            end
          elseif header.DF == 17
            % Extended squitter
            obj.NumTotalExtendedSquitter = obj.NumTotalExtendedSquitter + 1;
            if header.CRCError == false
              obj.NumGoodExtendedSquitter = obj.NumGoodExtendedSquitter + 1;
            end
          else
            obj.NumOtherModeSPackets = obj.NumOtherModeSPackets + 1;
          end
          
          if header.CRCError == false
            % Add packets without CRC errors to the table
            updateTable = true;
            
            % Search to find if the aircraft ID is already in the table
            newIdx = 0;
            idx = strcmp(tableData(:,ADSBFieldNames.ICAO24),currMsg.ICAO24);
            if any(idx)
              newIdx = find(idx);
            end
            
            % If this is a new aircraft ID, remove the oldest message from the
            % table
            if newIdx == 0
              [~,newIdx] = min([tableData{:,ADSBFieldNames.Time}]);
              tableData(newIdx,:) = {''};
              removePlaneFromMap(obj,newIdx)
            end
            
            % Set aircraft ID
            tableData{newIdx,ADSBFieldNames.ICAO24} = currMsg.ICAO24;
            
            switch currMsg.TC
              case {1 2 3 4}
                % Identification
                tableData{newIdx,ADSBFieldNames.FlightID} = ...
                  currMsg.Identification.FlightID;
              case {5 6 7 8}
                % Surface position
              case {9 10 11 12 13 14 15 16 17 18 20 21 22}
                % Airborne Position
                if ~isnan(currMsg.AirbornePosition.Latitude)
                  tableData{newIdx,ADSBFieldNames.Latitude} = ...
                    currMsg.AirbornePosition.Latitude;
                  tableData{newIdx,ADSBFieldNames.Longitude} = ...
                    currMsg.AirbornePosition.Longitude;
                end
                tableData{newIdx,ADSBFieldNames.Altitude} = ...
                  currMsg.AirbornePosition.Altitude;
              case 19
                if ~isnan(currMsg.AirborneVelocity.Speed)
                  tableData{newIdx,ADSBFieldNames.Speed} = ...
                    currMsg.AirborneVelocity.Speed;
                else
                  tableData{newIdx,ADSBFieldNames.Speed} = ...
                    'N/A';
                end
                if ~isnan(currMsg.AirborneVelocity.Heading)
                  tableData{newIdx,ADSBFieldNames.Heading} = ...
                    sprintf('%d (%s)', currMsg.AirborneVelocity.Heading, ...
                    currMsg.AirborneVelocity.HeadingSymbol);
                else
                  tableData{newIdx,ADSBFieldNames.Heading} = ...
                    sprintf('N/A (N/A)');
                end
                tableData{newIdx,ADSBFieldNames.HeadingSymbol} = ...
                  currMsg.AirborneVelocity.HeadingSymbol;
                tableData{newIdx,ADSBFieldNames.VerticalRate} = ...
                  currMsg.AirborneVelocity.VerticalRate;
              case 28
                % Extended Squitter Aircraft Status/ACAS RA
              case 31
                % Aircraft operational status
            end
            
            % datenum counts days. There are 86400 seconds in a day. Time is
            % in seconds. So, add Time/86400 days to RawStartTime, which is a
            % datenum.
            tableData{newIdx,ADSBFieldNames.Time} = ...
              obj.RawStartTime + header.Time/86400;
            tableData{newIdx,ADSBFieldNames.Current} = checkMark;
          end
        end
        
        if updateTable
          obj.TableData = tableData;
        end
      end
    end
    
    function write2File(obj,msg,msgCnt)
      if msgCnt > 0
        for p=1:msgCnt
          currMsg = msg(p);
          pos = currMsg.AirbornePosition;
          vel = currMsg.AirborneVelocity;
          id = currMsg.Identification;
          
          if currMsg.Header.DF == 11
            numBits = 56;
          elseif currMsg.Header.DF == 17
            numBits = 112;
          else
            numBits = 112;
          end
          hexMessage = helperAdsbBin2Hex(currMsg.Header.RawBits(1:numBits,1));
          dateTime = addtodate(obj.RawStartTime, ...
            round(currMsg.Header.Time*1e3), 'millisecond');
          
          fprintf(obj.FileHandle, ['%28s, %1d, %s, %2d, %1d, %s, %2d, ', ...
            '%24s, %8s, ', ...
            '%14s, %1d, %6d, %1d, %5s, %13.8f, %13.8f, ', ...
            '%19s, %1d, %1d, %1d, %4d, %4d, %s, %6d, %1d, %d\n'], ...
            hexMessage, ...
            currMsg.Header.CRCError, ...
            datestr(dateTime), ...
            currMsg.Header.DF, currMsg.Header.CA, currMsg.ICAO24, currMsg.TC, ...
            id.VehicleCategory, id.FlightID, ...
            pos.Status, pos.DiversityAntenna, pos.Altitude, ...
            pos.UTCSynchronized, pos.CPRFormat, pos.Latitude, pos.Longitude, ...
            vel.Subtype, vel.IntentChange, vel.IFRCapability, ...
            vel.VelocityUncertainty, vel.Speed, vel.Heading, ...
            vel.HeadingSymbol, vel.VerticalRate, vel.TurnIndicator, ...
            vel.GHD);
        end
      end
    end

    function initMapInfo(obj)
      map.Handle = -1;
      map.MarkerHandles = cell(obj.MaxNumMessages,1);
      map.MarkerData = zeros(obj.MaxNumMessages, 2);
      map.PlaneIconFolder = fileparts(mfilename('fullpath'));
      map.Timer = -1;
      map.FirstPlane = false;
      obj.Map = map;
    end
    
    function updateMap(obj,~,~)
      % Update map if only the user chose to open the map
      if obj.MapPlanes
        if isa(obj.Map.Handle, 'map.webmap.Canvas') ...
            && ~isvalid(obj.Map.Handle)
          launchMap(obj);
        else
          tableData = obj.TableData;
          markerData = obj.Map.MarkerData;
          for idx = 1:obj.MaxNumMessages
            % If this has lat/lon information and lat and lon are different
            % than the one on the map then update the plane icon
            lat = tableData{idx,ADSBFieldNames.Latitude};
            lon = tableData{idx,ADSBFieldNames.Longitude};
            if isa(lat,'double') && ~isnan(lat) ...
                && (markerData(idx,1) ~= lat) ...
                && (markerData(idx,2) ~= lon)
              addPlaneToMap(obj, tableData(idx,:), idx);
              markerData(idx,1) = lat;
              markerData(idx,2) = lon;
            end
          end
          obj.Map.MarkerData = markerData;
        end
      end
    end
    
    function launchMapCallback(obj,src,~)
      if src.Value == 1
        success = launchMap(obj);
        if ~success
          src.Value = 0;
        end
      else
        closeMap(obj);
      end
    end
    
    function logDataCallback(obj,src,~)
      if src.Value == 1
        startDataLog(obj);
      else
        stopDataLog(obj);
      end
    end
    
    function addPlaneToMap(obj, planeData, markerIdx)
      flightID = planeData{ADSBFieldNames.FlightID};
      heading = planeData{ADSBFieldNames.Heading};
      headingSym = planeData{ADSBFieldNames.HeadingSymbol};
      
      m = geopoint(planeData{ADSBFieldNames.Latitude},...
        planeData{ADSBFieldNames.Longitude});
      m.Altitude = planeData{ADSBFieldNames.Altitude};
      m.Speed = planeData{ADSBFieldNames.Speed};
      m.Direction = heading;
      m.AircraftID = planeData{ADSBFieldNames.ICAO24};
      
      attribspec = makeattribspec(m);
      
      desiredAttributes = {'AircraftID', 'Altitude', 'Speed', 'Direction'};
      allAttributes = fieldnames(attribspec);
      attributes = setdiff(allAttributes, desiredAttributes);
      attribspec = rmfield(attribspec, attributes);
      attribspec.AircraftID.AttributeLabel = '<b>AircraftID</b>';
      attribspec.Altitude.Format = '%s';
      attribspec.Altitude.AttributeLabel = '<b>Altitude</b>';
      attribspec.Altitude.Format = '%d Ft';
      attribspec.Speed.AttributeLabel = '<b>Speed</b>';
      attribspec.Speed.Format = '%d Knots';
      attribspec.Direction.AttributeLabel = '<b>Direction</b>';
      attribspec.Direction.Format = '%.4f degrees';
      
      pngFolder = obj.Map.PlaneIconFolder;
      if ~isequal(headingSym,'')
        switch(headingSym(1:2))
          case 'N '
            icon = fullfile( pngFolder , 'AirplaneN.png');
            iconScale = 1.5;
          case 'S '
            icon = fullfile( pngFolder , 'AirplaneS.png');
            iconScale = 1.5;
          case 'E '
            icon = fullfile( pngFolder , 'AirplaneE.png');
            iconScale = 1.5;
          case 'W '
            icon = fullfile( pngFolder , 'AirplaneW.png');
            iconScale = 1.5;
          case 'NE'
            icon = fullfile( pngFolder , 'AirplaneNE.png');
            iconScale = 1.5;
          case 'NW'
            icon = fullfile( pngFolder , 'AirplaneNW.png');
            iconScale = 1.5;
          case 'SE'
            icon = fullfile( pngFolder , 'AirplaneSE.png');
            iconScale = 1.5;
          case 'SW'
            icon = fullfile( pngFolder , 'AirplaneSW.png');
            iconScale = 1.5;
          otherwise
            icon = fullfile( pngFolder , 'AirplaneN.png');
            iconScale = 1.5;
        end
      else
        icon = fullfile( pngFolder , 'AirplaneN.png');
        iconScale = 1.5;
      end

      if obj.Map.FirstPlane == false
        obj.Map.FirstPlane = true;
        wmcenter(planeData{ADSBFieldNames.Latitude},...
        planeData{ADSBFieldNames.Longitude},obj.MapZoomLevel);
      end

      % First create a new marker
      tmpMarker = ...
        wmmarker(m,'Icon',icon,...
        'FeatureName',['Flight # - ' flightID],...
        'Description',attribspec,...
        'IconScale',iconScale,'AutoFit',false);
      
      if isa(obj.Map.MarkerHandles{markerIdx}, 'map.webmap.MarkerOverlay') ...
          && isvalid(obj.Map.MarkerHandles{markerIdx})
        % Then delete the old one, if it exists
        wmremove(obj.Map.MarkerHandles{markerIdx})
      end
      
      obj.Map.MarkerHandles{markerIdx} = tmpMarker;
    end
    
    function removePlaneFromMap(obj,markerIdx)
      if isa(obj.Map.MarkerHandles{markerIdx}, 'map.webmap.MarkerOverlay') ...
          && isvalid(obj.Map.MarkerHandles{markerIdx})
        % Then delete the old one, if it exists
        wmremove(obj.Map.MarkerHandles{markerIdx})
        markerData = obj.Map.MarkerData;
        markerData(markerIdx,1) = 0;
        markerData(markerIdx,2) = 0;
        obj.Map.MarkerData = markerData;
      end
    end
    
    function initProgressBar(obj)
      % Create a timer object for progress indicator
      count = 0;
      progressBar.Count = count;

      progressBar.Timer = timer(...
        'BusyMode', 'drop', ...
        'ExecutionMode', 'fixedRate', ...
        'Name', 'PlaneAnimation', ...
        'ObjectVisibility', 'off', ...
        'Period', 1, ...
        'StartDelay', 1, ...
        'TimerFcn', @obj.updateProgressBar);
      
      obj.ProgressBar = progressBar;
    end
    
    function updateProgressBar(obj, ~, ~)
      %updateProgressBar ADS-B progress indicator
      %   updateProgressBar(T,~,~) creates a progress indicator on the GUI.
      count = obj.ProgressBar.Count;

      switch count
        case 0
          obj.GUIHandles.ProgressIndicator.String = 'Receiving';
        case 1
          obj.GUIHandles.ProgressIndicator.String = 'Receiving.';
        case 2
          obj.GUIHandles.ProgressIndicator.String = 'Receiving..';
        case 3
          obj.GUIHandles.ProgressIndicator.String = 'Receiving...';
        case 4
          obj.GUIHandles.ProgressIndicator.String = 'Receiving....';
        case 5
          obj.GUIHandles.ProgressIndicator.String = 'Receiving.....';
      end
      
      count = count + 1;
      count = mod(count,6);
      
      obj.ProgressBar.Count = count;
      
      % Update radio status
      obj.GUIHandles.LostFlag.String = int2str(obj.Lost);
      
      drawnow
    end
    
    function cleanupGUI(obj,~,~)
      if isa(obj.ProgressBar.Timer,'timer') && isvalid(obj.ProgressBar.Timer)
        stop(obj.ProgressBar.Timer)
        delete(obj.ProgressBar.Timer)
      end
      if isa(obj.Map.Timer,'timer') && isvalid(obj.Map.Timer)
        stop(obj.Map.Timer)
        delete(obj.Map.Timer)
      end
      if isa(obj.Map.Handle, 'map.webmap.Canvas') && isvalid(obj.Map.Handle)
        wmclose(obj.Map.Handle);
      end
    end
  end
end

function closeMapCallback(obj,hTimer)
obj.LaunchMapvalue = 0;
obj.Map.FirstPlane = false;
obj.Map.MarkerData = zeros(obj.MaxNumMessages, 2);
if isa(hTimer,'timer') && isvalid(hTimer)
  stop(hTimer)
  delete(hTimer)
end
end

function [Duration] = getInputParam(preconfigObj)
%% 获取用户输入
% 返回一个配置好的结构体,这个结构体包含需要用户输入的所有必要参数
% 如果obj.preconfig已经被置位为true, 则直接返回obj, 否则引导用户输入

    if preconfigObj.preConfig == 1
        Duration = preconfigObj.Duration;
    else
        %要求用户输入运行时间
        inputedDuration = input(...
            sprintf('\n  请输入运行时间（单位为秒）（默认为[%f])：', preconfigObj.Duration));
        if ~isempty(inputedDuration)
            %这里是从官方文档抄的检验输入是否合法的函数
            validateattributes(inputedDuration,{'numeric'},{'scalar','real','positive','nonnan'}, '', 'Run Time');
            %验证没什么问题了, 可以直接拿去用了的Duration参数,放进即将返回的结构里
            Duration.Duration = inputedDuration;
        end
        
    end
        
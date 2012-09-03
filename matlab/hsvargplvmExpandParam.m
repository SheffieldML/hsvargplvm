function model = hsvargplvmExpandParam(model, params)

% HSVARGPLVMEXPANDPARAM Expand a parameter vector into a hierarchical variational GP-LVM model.
% FORMAT
% DESC takes a HSVARGPLVM structure and a vector of parameters, and
% fills the structure with the given parameters. Also performs any
% necessary precomputation for likelihood and gradient
% computations, so can be computationally intensive to call.

startVal = 0;
endVal = 0;
for h=1:model.H %%% FOR EACH LAYER
    startVal = endVal + 1;
    endVal = endVal + model.layer{h}.vardist.nParams;
    model.layer{h}.vardist = modelExpandParam(model.layer{h}.vardist, params(startVal:endVal)); 
    totLayerParams = 0;
    for m = 1:model.layer{h}.M  %%% FOR EACH SUB-MODEL in the same layer
        endValPrev = endVal;
        %--- inducing inputs 
        startVal = endVal+1;
        if model.layer{h}.comp{m}.fixInducing
            model.layer{h}.comp{m}.X_u = model.layer{h}.vardist.means(model.layer{h}.comp{m}.inducingIndices, :); % static
            % X_u values are taken from X values.
            % model.X_u = model.X(model.inducingIndices, :);
        else
            % Parameters include inducing variables.
            endVal = endVal + model.layer{h}.q*model.layer{h}.comp{m}.k;
            model.layer{h}.comp{m}.X_u = reshape(params(startVal:endVal),model.layer{h}.comp{m}.k,model.layer{h}.q);
        end
        
        %--- kernel hyperparameters
        startVal = endVal+1;
        endVal = endVal + model.layer{h}.comp{m}.kern.nParams;
        model.layer{h}.comp{m}.kern = kernExpandParam(model.layer{h}.comp{m}.kern, params(startVal:endVal));

        %--- likelihood beta parameters
        if model.layer{h}.comp{m}.optimiseBeta
            startVal = endVal + 1;
            endVal = endVal + prod(size(model.layer{h}.comp{m}.beta));
            if ~isstruct(model.layer{h}.comp{m}.betaTransform)
                fhandle = str2func([model.layer{h}.comp{m}.betaTransform 'Transform']);
                model.layer{h}.comp{m}.beta = fhandle(params(startVal:endVal), 'atox');
            else
                if isfield(model.layer{h}.comp{m}.betaTransform,'transformsettings') && ~isempty(model.layer{h}.comp{m}.betaTransform.transformsettings)
                    fhandle = str2func([model.layer{h}.comp{m}.betaTransform.type 'Transform']);
                    model.layer{h}.comp{m}.beta = fhandle(params(startVal:endVal), 'atox', model.layer{h}.comp{m}.betaTransform.transformsettings);
                else
                    error('vargplvmExtractParam: Invalid transform specified for beta.');
                end
            end
        end
        model.layer{h}.comp{m}.nParams = endVal - endValPrev;
        totLayerParams = totLayerParams + model.layer{h}.comp{m}.nParams;
    end
    model.layer{h}.nParams = totLayerParams + model.layer{h}.vardist.nParams;
end
model.nParams = endVal;

%%% TODO
model = hsvargplvmUpdateStats(model);

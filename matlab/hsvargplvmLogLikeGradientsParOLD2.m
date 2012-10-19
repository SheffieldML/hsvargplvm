
% Function identical to hsvargplvmLogLikeGradients but optimised for
% parallel computation w.r.t the submodels in each layer.
function g = hsvargplvmLogLikeGradientsPar(model)

g_leaves = hsvargplvmLogLikeGradientsLeaves(model.layer{1});
[g_nodes g_sharedLeaves] = hsvargplvmLogLikeGradientsNodes(model);
% Amend the vardistr. derivatives of the leaves only with those of the
% higher layer.
%%% TEMP %%%% !!
%g_leaves(1:model.layer{1}.vardist.nParams) = g_leaves(1:model.layer{1}.vardist.nParams).*0;
%%%%%%%%%%
g_leaves(1:model.layer{1}.vardist.nParams) = g_leaves(1:model.layer{1}.vardist.nParams) + g_sharedLeaves;

g_entropies = hsvargplvmLogLikeGradientsEntropies(model);

% This is the gradient of the entropies (only affects covars). It's just -0.5*I
N = model.layer{1}.N;
Q1 = model.layer{1}.q;
%g_entropies = -0.5.*g_leaves(N*Q1+1:model.layer{1}.vardist.nParams);
g_leaves(N*Q1+1:model.layer{1}.vardist.nParams) = g_leaves(N*Q1+1:model.layer{1}.vardist.nParams) + g_entropies;
for h=2:model.H-1
    N = model.layer{1}.N;
    Q1 = model.layer{1}.q;
    % g_entropies is the same for all models (constant)
    % TODO!!!
    % g_nodes(indicesForCovarsInThisNode)=g_nodes(indicesForCovarsInThisNode)+g_entropies;
end
g = [g_leaves  g_nodes];

dynUsed = (isfield(model.layer{end},'dynamics') && ~isempty(model.layer{end}.dynamics));
% We only have to amend the parent's var. distr. derivatives if there are
% no dynamics, because then the derivs. are only calculated from the
% likelihood term. If there are dynamics, the derivs are calculated from
% the svargplvm function including the KL part.
if ~dynUsed
    % Amend the derivatives of the parent's var.distr. with the terms coming
    % from the KL.
    g_parent = hsvargplvmLogLikeGradientsParent(model.layer{model.H});
    startInd = model.nParams-model.layer{model.H}.nParams+1;
    endInd = startInd + model.layer{model.H}.vardist.nParams-1;
    g(startInd:endInd) = g(startInd:endInd) + g_parent;
else
    warning('This function has not been tested very well when there are dynamics!!!')
end

end



function g = hsvargplvmLogLikeGradientsLeaves(model)

g = [];
gShared = zeros(1, model.vardist.nParams);
g_i = cell(1, model.M);
modelComp = model.comp;
vardist = model.vardist;
parfor i=1:model.M
    modelComp{i}.vardist = vardist;
    modelComp{i}.onlyLikelihood = true;
    g_i{i} = vargplvmLogLikeGradients(modelComp{i});
end
for i=1:model.M
    % Now add the derivatives for the shared parameters (vardist)
    gShared = gShared + g_i{i}(1:model.vardist.nParams);
    g_i{i} = g_i{i}((model.vardist.nParams+1):end);
    g = [g g_i{i}];
end
g = [gShared g];
end

% g: The gradients for the "likelihood"+vardist part (ie no entropies, no
% KL) of all nodes
% gSharedLeaves: The gradients for the vardist part of the variational
% distribution of the first layer only, which has to be amended with the
% gradient obtained by hsvargplvmLogLikeGradientsLeaves. The vardist.
% gradients of the variational distributions of the other layers (apart from
% the parent) is handled internally (no need if H == 2)
function [g gSharedLeaves] = hsvargplvmLogLikeGradientsNodes(model)
g=[]; % Final derivative
gSharedLeavesMeans = zeros(model.layer{1}.N, model.layer{1}.q);
gSharedLeavesCovars = zeros(model.layer{1}.N, model.layer{1}.q);

for h=2:model.H
    dynUsed = false;
    if (h==model.H && (isfield(model.layer{h},'dynamics') && ~isempty(model.layer{h}.dynamics)));
        dynUsed = true;
    end
    
    g_h = []; % Derivative wrt params of layer h
    model_h = model.layer{h};
    model_hVardist = model.layer{h}.vardist;
    model_hComp = model.layer{h}.comp;
    %model_hprev = model.layer{h-1};
    model_hprevVardistMeans = model.layer{h-1}.vardist.means;
    model_hprevVardistCovars = model.layer{h-1}.vardist.covars;
    %gShared = zeros(1, model.layer{h}.vardist.nParams); % Derivatives of the var. distr. of layer h
    g_i = cell(1, model_h.M);
    latInd = cell(1, model_h.M);
    gSharedLeavesMeansPart = cell(1, model_h.M);
    gSharedLeavesCovarsPart = cell(1, model_h.M);
    for i=1:model_h.M
        latInd{i} = 1:model.layer{h-1}.vardist.latentDimension;
    end
    
    if ~dynUsed
        gShared = 0;
        
        parfor i=1:model_h.M % Derivative of the likelihood term of the m-th model of layer h
            
            model_hComp{i}.vardist = model_hVardist;
            model_hComp{i}.onlyLikelihood = true;
            
            % Calculates the derivatives for the vardist. params and the other
            % params (apart from the KL) of the layer h > 1
            g_i{i} = vargplvmLogLikeGradients(model_hComp{i});
            
            % Now add the derivatives for the shared parameters (vardist)
            gSharedPart{i} = g_i{i}(1:model_hVardist.nParams);
            
            % g_i will now hold all the non-vardist. derivatives (the rest are
            % taken care of in gShared)
            g_i{i} = g_i{i}((model_hVardist.nParams+1):end);
            gShared = gShared + gSharedPart{i};
            
        end
        for i=1:model_h.M
            g_h = [g_h g_i{i}];
        end
        g_h = [gShared g_h];
    else
        model.layer{h}.numModels = model.layer{h}.M;
        for i=1:model.layer{h}.M
            model.layer{h}.comp{i}.vardist = model.layer{h}.vardist;
            model.layer{h}.comp{i}.dynamics = model.layer{h}.dynamics;
        end
        g_h = svargplvmLogLikeGradients(model.layer{h});
    end
    
    g_sharedPrevNode = zeros(1,model.layer{h-1}.vardist.nParams);
    gSharedNodeMeans = zeros(model.layer{h-1}.N, model.layer{h-1}.q);
    gSharedNodeCovars = zeros(model.layer{h-1}.N, model.layer{h-1}.q);
    
    % Find the quantity that needs to be added to the PREVIOUS gShared.
    % This quantity is either the 'gSharedLeaves' which is returned and
    % added outside of this function (in the main body) or the
    % gSharedPrevNode , which is added in this function, after this for
    % loop finishes.
    for i=1:model.layer{h}.M 
        means = model.layer{h-1}.vardist.means;
        covars = model.layer{h-1}.vardist.covars;
        
        %if model.centerMeans
        % TODO
        %end
        
        if ~isempty(model.layer{h}.comp{i}.latentIndices)
            latInd = model.layer{h}.comp{i}.latentIndices;
        else
            % All indices (M == 1)
            latInd = 1:model.layer{h-1}.vardist.latentDimension;
        end
        % In this layer h the "means" ie the X of layer h-1 are
        % here outputs. If we also have multOutput option, i.e. only
        % the full output space "means" will be grouped into
        % smaller subpsaces as defined in latentIndices. If we
        % don't have the multOutput>1 option, then means/covars will be the
        % original ones.
        means = means(:, latInd);
        covars = covars(:, latInd);
        
            %-- Amend the gShared OF THE PREVIOUS LAYER with the new terms due to the expectation
        % If multOutput(h) is set, then the expectation of <\tilde{F}>_{q(X_{h-1}} will
        % be split into Q expectations wrt q(X_{h-1}(:,q)), q=1,...,Q. In
        % general (not tested yet!!!) it will not be grouped by q, but
        % it could be defined as arbitrary subsets of X_{h-1}.
        beta = model.layer{h}.comp{i}.beta;
        if h == 2
            %-- Previous layer is leaves
            % Amend for the F3 term of the bound
            gSharedLeavesMeans(:, latInd) = beta * ...
                model.layer{h}.comp{i}.Z' * means;
            gSharedLeavesCovars(:, latInd) = 0.5*beta * ...
                repmat(diag(model.layer{h}.comp{i}.Z), 1, size(means,2));

            % Amend for the F0 term of the bound
            gSharedLeavesMeans(:, latInd) = gSharedLeavesMeans(:, latInd) - beta * means;
            gSharedLeavesCovars(:, latInd) = gSharedLeavesCovars(:, latInd) - 0.5*beta * ones(size(gSharedLeavesCovars(:, latInd)));

            % Reparametrization: from dF/dS -> dF/d log(S)
            gSharedLeavesCovars(:, latInd) = covars.*gSharedLeavesCovars(:, latInd);
        else % h > 2
           % error('H > 2 not implemented yet!!')
            % TODO!!!! For > 2 layers:
            % Previous layer is intermediate nodes
            % TODO: Here, we don't return the result but we added directly
            % to the previous iterations derivative (since everything
            % happens in the same function).
            
            % These computations are as above for the leaves case...
            
            % Amend for the F3 term of the bound
            gSharedNodeMeans(:, latInd) = beta * ...
                model.layer{h}.comp{i}.Z' * means;
            gSharedNodeCovars(:, latInd) = 0.5*beta * ...
                repmat(diag(model.layer{h}.comp{i}.Z), 1, size(means,2));

            % Amend for the F0 term of the bound
            gSharedNodeMeans(:, latInd) = gSharedNodeMeans(:, latInd) - beta * means;
            gSharedNodeCovars(:, latInd) = gSharedNodeCovars(:, latInd) - 0.5*beta * ones(size(gSharedNodeCovars(:, latInd)));

            % Reparametrization: from dF/dS -> dF/d log(S)
            gSharedNodeCovars(:, latInd) = covars.*gSharedNodeCovars(:, latInd);
            gSharedNodeVardist = [gSharedNodeMeans(:)' gSharedNodeCovars(:)'];

            g_sharedPrevNode(1:model.layer{h-1}.vardist.nParams) = ...
                    g_sharedPrevNode(1:model.layer{h-1}.vardist.nParams) + gSharedNodeVardist;

        end
        %--
    end
    
    % (for H > 2)
    if h > 2
        % The gShared of the PREVIOUS iteration needs to be augmented
           % Inds of the vardistr of the prev. node
        indStart = length(g) - model.layer{h-1}.nParams+1;
        indEnd = indStart + model.layer{h-1}.vardist.nParams - 1;
        g(indStart:indEnd) = g(indStart:indEnd) + g_sharedPrevNode;
    end
    
    % Now we can add the g_h of the current iteration
    g = [g g_h];

end
gSharedLeaves = [gSharedLeavesMeans(:)' gSharedLeavesCovars(:)'];
end


function g = hsvargplvmLogLikeGradientsEntropies(model)
g=-0.5*ones(1,model.layer{1}.N * model.layer{1}.q);
end

function gVar = hsvargplvmLogLikeGradientsParent(modelParent)

if isfield(modelParent, 'learnInducing')
    learnInducing = modelParent.learnInducing;
else
    learnInducing = true;
end


model = modelParent.comp{1};
model.vardist = modelParent.vardist;
gVarmeans = - model.vardist.means(:)';
% !!! the covars are optimized in the log space (otherwise the *
% becomes a / and the signs change)
gVarcovs = 0.5 - 0.5*model.vardist.covars(:)';


if isfield(model, 'fixInducing') & model.fixInducing
    % TODO!!!
    warning('Implementation for fixing inducing points is not complete yet...')
    % Likelihood terms (coefficients)
    [gK_uu, gPsi0, gPsi1, gPsi2, g_Lambda, gBeta, tmpV] = vargpCovGrads(model);
    
    % Get (in three steps because the formula has three terms) the gradients of
    % the likelihood part w.r.t the data kernel parameters, variational means
    % and covariances (original ones). From the field model.vardist, only
    % vardist.means and vardist.covars and vardist.lantentDimension are used.
    [gKern1, gVarmeans1, gVarcovs1, gInd1] = kernVardistPsi1Gradient(model.kern, model.vardist, model.X_u, gPsi1',learnInducing);
    [gKern2, gVarmeans2, gVarcovs2, gInd2] = kernVardistPsi2Gradient(model.kern, model.vardist, model.X_u, gPsi2,learnInducing);
    [gKern0, gVarmeans0, gVarcovs0] = kernVardistPsi0Gradient(model.kern, model.vardist, gPsi0,learnInducing);
    
    %%% Compute Gradients with respect to X_u %%%
    gKX = kernGradX(model.kern, model.X_u, model.X_u);
    % The 2 accounts for the fact that covGrad is symmetric
    gKX = gKX*2;
    dgKX = kernDiagGradX(model.kern, model.X_u);
    for i = 1:model.k
        gKX(i, :, i) = dgKX(i, :);
    end
    % Allocate space for gX_u
    gX_u = zeros(model.k, model.q);
    % Compute portion associated with gK_u
    for i = 1:model.k
        for j = 1:model.q
            gX_u(i, j) = gKX(:, j, i)'*gK_uu(:, i);
        end
    end
    % This should work much faster
    %gX_u2 = kernKuuXuGradient(model.kern, model.X_u, gK_uu);
    gInd = gInd1 + gInd2 + gX_u(:)';
    %gVarmeans(model.inducingIndices, :) = gVarmeans(model.inducingIndices,
    %:) + gInd; % This should work AFTER reshaping the matrices...but here
    %we use all the indices anyway.
    gVarmeans = gVarmeans + gInd;
end

gVar = [gVarmeans gVarcovs];
if isfield(model.vardist,'paramGroups')
    gVar = gVar*model.vardist.paramGroups;
end


end
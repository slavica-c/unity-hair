﻿Shader "Hidden/HairSimDebugDraw"
{
	HLSLINCLUDE

	#pragma target 5.0

	#pragma multi_compile_local __ LAYOUT_INTERLEAVED
	// 0 == particles grouped by strand, i.e. root, root+1, root, root+1
	// 1 == particles grouped by index, i.e. root, root, root+1, root+1
	
	#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
	#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"

	#include "HairSimData.hlsl"
	#include "HairSimComputeConfig.hlsl"
	#include "HairSimComputeVolumeUtility.hlsl"
	#include "HairSimDebugDrawUtility.hlsl"
	
	uint _DebugSliceAxis;
	float _DebugSliceOffset;
	float _DebugSliceDivider;
	float _DebugSliceOpacity;

	struct DebugVaryings
	{
		float4 positionCS : SV_POSITION;
		float4 color : TEXCOORD0;
	};

	DebugVaryings DebugVert_StrandParticle(uint instanceID : SV_InstanceID, uint vertexID : SV_VertexID)
	{
	#if LAYOUT_INTERLEAVED
		const uint strandParticleBegin = instanceID;
		const uint strandParticleStride = _StrandCount;
	#else
		const uint strandParticleBegin = instanceID * _StrandParticleCount;
		const uint strandParticleStride = 1;
	#endif

	#if DEBUG_STRAND_31_32 == 2
		if (vertexID > 1)
			vertexID = 1;
	#endif

		uint i = strandParticleBegin + strandParticleStride * vertexID;
		float3 worldPos = _ParticlePosition[i].xyz;

		//float volumeDensityShadow = 8.0;
		//float volumeDensity = VolumeSampleScalar(_VolumeDensity, VolumeWorldToUVW(worldPos));
		//float volumeOcclusion = saturate((volumeDensityShadow - volumeDensity) / volumeDensityShadow);// pow(1.0 - saturate(volumeDensity / 200.0), 4.0);

		DebugVaryings output;
		output.positionCS = TransformWorldToHClip(GetCameraRelativePositionWS(worldPos));
		output.color = float4(ColorCycle(instanceID, _StrandCount), 1.0);
		return output;
	}

	DebugVaryings DebugVert_StrandParticleMotion(uint instanceID : SV_InstanceID, uint vertexID : SV_VertexID)
	{
	#if LAYOUT_INTERLEAVED
		const uint strandParticleBegin = instanceID;
		const uint strandParticleStride = _StrandCount;
	#else
		const uint strandParticleBegin = instanceID * _StrandParticleCount;
		const uint strandParticleStride = 1;
	#endif

		uint i = strandParticleBegin + strandParticleStride * vertexID;
		float3 worldPos0 = _ParticlePositionPrev[i].xyz;
		float3 worldPos1 = _ParticlePosition[i].xyz;

		float4 clipPos0 = mul(UNITY_MATRIX_PREV_VP, float4(GetCameraRelativePositionWS(worldPos0), 1.0));
		float4 clipPos1 = mul(UNITY_MATRIX_UNJITTERED_VP, float4(GetCameraRelativePositionWS(worldPos1), 1.0));

		float2 ndc0 = clipPos0.xy / clipPos0.w;
		float2 ndc1 = clipPos1.xy / clipPos1.w;

		DebugVaryings output;
		output.positionCS = TransformWorldToHClip(GetCameraRelativePositionWS(worldPos1));
		output.color = float4(0.5 * (ndc1 - ndc0), 0, 0);
		return output;
	}

	DebugVaryings DebugVert_VolumeDensity(uint vertexID : SV_VertexID)
	{
		uint3 volumeIdx = VolumeFlatIndexToIndex(vertexID);
		float volumeDensity = _VolumeDensity[volumeIdx];
		float3 worldPos = (volumeDensity == 0.0) ? 1e+7 : VolumeIndexToWorld(volumeIdx);

		DebugVaryings output;
		output.positionCS = TransformWorldToHClip(GetCameraRelativePositionWS(worldPos));
		output.color = float4(ColorDensity(volumeDensity), 1.0);
		return output;
	}

	DebugVaryings DebugVert_VolumeGradient(uint vertexID : SV_VertexID)
	{
		uint3 volumeIdx = VolumeFlatIndexToIndex(vertexID >> 1);
		float3 volumeGradient = _VolumePressureGrad[volumeIdx];
		float3 worldPos = VolumeIndexToWorld(volumeIdx);

		if (vertexID & 1)
		{
			worldPos -= volumeGradient;
		}

		DebugVaryings output;
		output.positionCS = TransformWorldToHClip(GetCameraRelativePositionWS(worldPos));
		output.color = float4(ColorGradient(volumeGradient), 1.0);
		return output;
	}

	DebugVaryings DebugVert_VolumeSlice(uint vertexID : SV_VertexID)
	{
		float3 uvw = float3(((vertexID >> 1) ^ vertexID) & 1, vertexID >> 1, _DebugSliceOffset);
		float3 uvwWorld = (_DebugSliceAxis == 0) ? uvw.zxy : (_DebugSliceAxis == 1 ? uvw.xzy : uvw.xyz);
		float3 worldPos = lerp(_VolumeWorldMin, _VolumeWorldMax, uvwWorld);

		uvw = uvwWorld;

		DebugVaryings output;
		output.positionCS = TransformWorldToHClip(GetCameraRelativePositionWS(worldPos));
		output.color = float4(uvw, 1);
		return output;
	}

	float4 DebugFrag(DebugVaryings input) : SV_Target
	{
		return input.color;
	}

	float4 DebugFrag_VolumeSlice(DebugVaryings input) : SV_Target
	{
		float3 uvw = input.color.xyz;

		float3 localPos = VolumeUVWToLocal(uvw);
		float3 localPosFloor = round(0.5 + localPos);

		float3 gridAxis = float3(_DebugSliceAxis != 0, _DebugSliceAxis != 1, _DebugSliceAxis != 2);
		float3 gridDist = gridAxis * abs(localPos - localPosFloor);
		float3 gridWidth = gridAxis * fwidth(localPos);

		if (any(gridDist < gridWidth))
		{
			uint i = ((uint)localPosFloor[_DebugSliceAxis]) % 3;
			return float4(0.2 * float3(i == 0, i == 1, i == 2), _DebugSliceOpacity);
		}

		float volumeDensity = VolumeSampleScalar(_VolumeDensity, uvw);
		float3 volumeVelocity = VolumeSampleVector(_VolumeVelocity, uvw);
		float volumeDivergence = VolumeSampleScalar(_VolumeDivergence, uvw);
		float volumePressure = VolumeSampleScalar(_VolumePressure, uvw);
		float3 volumePressureGrad = VolumeSampleVector(_VolumePressureGrad, uvw);

		// test fake level-set
		/*
		if (_DebugSliceDivider == 2.0)
		{
			float3 step = VolumeLocalToUVW(1.0);
			float d_min = 1e+4;
			float r_max = 0.0;

			for (int i = -1; i <= 1; i++)
			{
				for (int j = -1; j <= 1; j++)
				{
					float3 uvw_xz = float3(
						uvw.x + i * step.x,
						uvw.y,
						uvw.z + j * step.z);

					float vol = abs(VolumeSampleScalar(_VolumeDensity, uvw_xz));
					if (vol > 0.0)
					{
						float vol_d = length(float2(i, j));
						float vol_r = pow((3.0 * vol) / (4.0 * 3.14159), 1.0 / 3.0);

						d_min = min(d_min, vol_d - vol_r);
						r_max = max(r_max, vol_r);
					}
				}
			}

			float4 color_air = float4(0.0, 0.0, 0.0, 1.0);
			float4 color_int = float4(1.0, 0.0, 0.0, 1.0);
			float4 color_ext = float4(1.0, 1.0, 0.0, 1.0);

			return float4(r_max.xxx, 1.0);

			if (d_min == 1e+4)
				return color_air;
			else if (d_min < -0.5)
				return color_int * float4(-d_min.xxx, 1.0);
			else
				return color_ext * float4(1.0 - d_min.xxx, 1.0);
		}
		*/

		float x = uvw.x + _DebugSliceDivider;
		if (x < 1.0)
			return float4(ColorDensity(volumeDensity), _DebugSliceOpacity);
		else if (x < 2.0)
			return float4(ColorVelocity(volumeVelocity), _DebugSliceOpacity);
		else if (x < 3.0)
			return float4(ColorDivergence(volumeDivergence), _DebugSliceOpacity);
		else if (x < 4.0)
			return float4(ColorPressure(volumePressure), _DebugSliceOpacity);
		else
			return float4(ColorGradient(volumePressureGrad), _DebugSliceOpacity);
	}

	ENDHLSL

	SubShader
	{
		Cull Off
		ZTest LEqual
		ZWrite On

		Pass// 0 == STRAND PARTICLE
		{
			HLSLPROGRAM

			#pragma vertex DebugVert_StrandParticle
			#pragma fragment DebugFrag

			ENDHLSL
		}

		Pass// 1 == STRAND PARTICLE MOTION
		{
			HLSLPROGRAM

			#pragma vertex DebugVert_StrandParticleMotion
			#pragma fragment DebugFrag

			ENDHLSL
		}

		Pass// 2 == VOLUME DENSITY
		{
			HLSLPROGRAM

			#pragma vertex DebugVert_VolumeDensity
			#pragma fragment DebugFrag

			ENDHLSL
		}

		Pass// 3 == VOLUME GRADIENT
		{
			HLSLPROGRAM

			#pragma vertex DebugVert_VolumeGradient
			#pragma fragment DebugFrag

			ENDHLSL
		}

		Pass// 4 == VOLUME SLICE
		{
			ZTest LEqual
			Blend SrcAlpha OneMinusSrcAlpha

			HLSLPROGRAM

			#pragma vertex DebugVert_VolumeSlice
			#pragma fragment DebugFrag_VolumeSlice

			ENDHLSL
		}

		Pass// 5 == VOLUME SLICE (BELOW)
		{
			ZWrite Off
			ZTest Greater
			Blend SrcAlpha OneMinusSrcAlpha

			HLSLPROGRAM

			#pragma vertex DebugVert_VolumeSlice
			#pragma fragment DebugFrag_VolumeSlice

			ENDHLSL
		}
	}
}
